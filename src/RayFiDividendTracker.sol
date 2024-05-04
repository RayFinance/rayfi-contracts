// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRayFiToken} from "./IRayFiToken.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract RayFiDividendTracker is Ownable {
    /////////////////////
    // State Variables //
    /////////////////////

    uint256 private constant MAGNITUDE = 2 ** 128;

    uint256 private s_magnifiedPrismaPerShare;
    uint256 private s_magnifiedDividendPerShare;
    uint256 private s_lastDistribution;
    uint256 private s_lastProcessedIndex;
    uint256 private s_totalDividendsDistributed;

    bool private s_processingAutoReinvest;

    mapping(address => uint256) private s_withdrawnDividends;

    IRayFiToken private s_rayFiToken;
    IUniswapV2Router02 private s_router;

    address private s_dividendToken;
    address private s_treasuryReceiver;
    address private s_rayFundReceiver;

    ////////////////
    /// Events    //
    ////////////////

    /**
     * @notice Emitted when the minimum token balance for dividends is updated
     * @param newMinimum The new minimum token balance for dividends
     * @param oldMinimum The previous minimum token balance for dividends
     */
    event MinimumTokenBalanceForDividendsUpdated(uint256 indexed newMinimum, uint256 indexed oldMinimum);

    /**
     * @notice Emitted when the gas amount for processing is updated
     * @param newGas The new gas amount for processing
     * @param oldGas The previous gas amount for processing
     */
    event GasForProcessingUpdated(uint256 indexed newGas, uint256 indexed oldGas);

    /**
     * @notice Emitted when dividends are distributed
     * @param dividendPerShare The dividend amount per share
     * @param totalDividendsDistributed The total dividends that have been distributed
     * @param lastDistribution Distribution offset to avoid double counting
     */
    event DividendsDistributed(
        uint256 indexed dividendPerShare, uint256 indexed totalDividendsDistributed, uint256 indexed lastDistribution
    );

    /**
     * @notice Emitted when dividends are withdrawn
     * @param account The account that withdrew the dividends
     * @param amount The amount of dividends that were withdrawn
     */
    event DividendsWithdrawn(address indexed account, uint256 indexed amount);

    /**
     * @notice Emitted when dividends are reinvested
     * @param account The account that reinvested the dividends
     * @param amount The amount of dividends that were reinvested
     * @param lastDistribution Distribution offset to avoid double counting
     * @param manual A flag indicating whether the reinvestment was manual
     */
    event DividendsReinvested(
        address indexed account, uint256 indexed amount, uint256 indexed lastDistribution, bool manual
    );

    //////////////////
    // Errors       //
    //////////////////

    /**
     * @dev Triggered when attempting to set the zero address as a contract parameter
     * Setting a contract parameter to the zero address can lead to unexpected behavior
     */
    error RayFiDividendTracker__CannotSetToZeroAddress();

    /**
     * @notice Triggered when trying to transfer tracker tokens directly
     * The underlying dividend tokens should be transferred instead
     */
    error RayFiDividendTracker__TransfersAreDisabled();

    /**
     * @notice Triggered when trying to reassign the current value to a variable
     * @dev Reassigning the same value to a variable costs more gas than checking the value first
     */
    error RayFiDividendTracker__CannotReassignToTheSameValue();

    /**
     * @notice Triggered when trying to call a function that is only callable by the RayFi Token contract
     */
    error RayFiDividendTracker__OnlyCallableByRayFiToken();

    /**
     * @dev Triggered when trying to process dividends, but there are no shareholders
     */
    error RayFiDividendTracker__ZeroShareholders();

    /**
     * @dev Triggered when trying to process dividends, but not enough gas was sent with the transaction
     */
    error RayFiDividendTracker__InsufficientGas();

    ////////////////////
    // Constructor    //
    ////////////////////

    /**
     * @notice Initializes the Dividend Tracker with the necessary contract references
     * @dev Sets the initial state of the contract, including the minimum token balance to be eligible for dividends
     * @param dividendToken The address of the ERC20 token that will be used to distribute dividends
     * @param router The address of the Uniswap router for handling liquidity operations
     * @param rayFiToken The address of the RayFi Token contract
     */
    constructor(
        address dividendToken,
        address router,
        address rayFiToken,
        address treasuryReceiver,
        address rayFundReceiver
    ) Ownable(msg.sender) {
        if (
            dividendToken == address(0) || router == address(0) || rayFiToken == address(0)
                || treasuryReceiver == address(0) || rayFundReceiver == address(0)
        ) {
            revert RayFiDividendTracker__CannotSetToZeroAddress();
        }

        s_dividendToken = dividendToken;
        s_rayFiToken = IRayFiToken(rayFiToken);
        s_router = IUniswapV2Router02(router);
        s_treasuryReceiver = treasuryReceiver;
        s_rayFundReceiver = rayFundReceiver;
    }

    ////////////////////////////////////
    // External & Public Functions    //
    ////////////////////////////////////

    /**
     * @notice Distributes stablecoins to token holders as dividends.
     * @dev It reverts if the total supply of tokens is 0.
     * About undistributed stablecoins:
     *   In each distribution, there is a small amount of stablecoins not distributed,
     *     the magnified amount of which is
     *     `(amount * magnitude) % totalSupply()`.
     *   With a well-chosen `magnitude`, the amount of undistributed stablecoins
     *     (de-magnified) in a distribution can be less than 1 wei.
     *   We can actually keep track of the undistributed stablecoins in a distribution
     *     and try to distribute it in the next distribution,
     *     but keeping track of such data on-chain costs much more than
     *     the saved stablecoins, so we don't do that.
     */
    function distributeDividends(uint256 gasForDividends, bool processDividends) external onlyOwner {
        uint256 amount = IERC20(s_dividendToken).balanceOf(address(this)) - s_lastDistribution;
        if (amount > 0) {
            s_magnifiedDividendPerShare += (amount * MAGNITUDE) / IERC20(address(s_rayFiToken)).totalSupply();

            s_totalDividendsDistributed += amount;

            if (processDividends) {
                _process(gasForDividends, false);
                autoReinvest(gasForDividends);
            }

            s_lastDistribution = IERC20(s_dividendToken).balanceOf(address(this));

            emit DividendsDistributed(s_magnifiedDividendPerShare, s_totalDividendsDistributed, s_lastDistribution);
        }
    }

    /**
     * @notice Swaps the fees collected by the token contract for stablecoin and allocates them
     * @dev Since Uniswap does not allow setting the recipient of a swap as one of the tokens
     * being swapped, it is impossible to collect the swapped fees directly in the main contract
     */
    function swapFees() external {
        if (msg.sender != address(s_rayFiToken)) {
            revert RayFiDividendTracker__OnlyCallableByRayFiToken();
        }

        uint256 dividendBalanceBefore = IERC20(s_dividendToken).balanceOf(address(this));
        uint256 rayFiBalance = IERC20(address(s_rayFiToken)).balanceOf(address(this));

        (
            uint256 buyLiquidityFee,
            uint256 buyTreasuryFee,
            uint256 buyRayFundFee,
            uint256 sellLiquidityFee,
            uint256 sellTreasuryFee,
            uint256 sellRayFundFee
        ) = s_rayFiToken.getFeeAmounts();
        uint256 liquidityFee = buyLiquidityFee + sellLiquidityFee;
        uint256 treasuryFee = buyTreasuryFee + sellTreasuryFee;
        uint256 totalFees = liquidityFee + treasuryFee + buyRayFundFee + sellRayFundFee;

        uint256 rayFiForLiquidity;
        if (liquidityFee > 0) {
            rayFiForLiquidity = (liquidityFee * rayFiBalance) / 100;
        }

        uint256 swapAmount = rayFiBalance - rayFiForLiquidity;
        IERC20(address(s_rayFiToken)).approve(address(s_router), swapAmount);
        address[] memory path = new address[](2);
        path[0] = address(s_rayFiToken);
        path[1] = s_dividendToken;
        s_router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            swapAmount, 0, path, address(this), block.timestamp
        );

        uint256 dividendBalanceAfter = IERC20(s_dividendToken).balanceOf(address(this));
        uint256 collectedFees = dividendBalanceAfter - dividendBalanceBefore;

        uint256 dividendForLiquidity = (collectedFees * liquidityFee) / (totalFees);
        if (rayFiForLiquidity > 0) {
            IERC20(address(s_rayFiToken)).approve(address(s_router), rayFiForLiquidity);
            IERC20(address(s_dividendToken)).approve(address(s_router), dividendForLiquidity);
            (, uint256 amountB,) = s_router.addLiquidity(
                address(s_rayFiToken),
                s_dividendToken,
                rayFiForLiquidity,
                dividendForLiquidity,
                0,
                0,
                msg.sender,
                block.timestamp
            );
            collectedFees -= amountB;
        }

        uint256 dividendForTreasury = (collectedFees * treasuryFee) / (totalFees);
        IERC20(s_dividendToken).transfer(s_treasuryReceiver, dividendForTreasury);
        collectedFees -= dividendForTreasury;

        IERC20(s_dividendToken).transfer(s_rayFundReceiver, collectedFees);
    }

    /**
     * @notice Sets the address for the token used for dividend payout
     * @dev This should be an ERC20 token
     */
    function setDividendTokenAddress(address newToken) external onlyOwner {
        s_dividendToken = newToken;
    }

    /////////////////////////////////////////
    // External & Public View Functions    //
    /////////////////////////////////////////

    /**
     * @notice Returns the total amount of dividends distributed by the contract
     *
     */
    function getTotalDividendsDistributed() external view returns (uint256) {
        return s_totalDividendsDistributed;
    }

    /**
     * @notice Get the treasury receiver
     * @return The address of the treasury receiver
     */
    function getTreasuryReceiver() external view returns (address) {
        return s_treasuryReceiver;
    }

    /**
     * @notice Get the RAY fund receiver
     * @return The address of the RAY fund receiver
     */
    function getRayFundReceiver() external view returns (address) {
        return s_rayFundReceiver;
    }

    /**
     * @notice View the amount of dividend in wei that an address can withdraw.
     * @param account The address of a token holder.
     * @return The amount of dividend in wei that `account` can withdraw.
     */
    function withdrawableDividendOf(address account) public view returns (uint256) {
        return accumulativeDividendOf(account) - s_withdrawnDividends[account];
    }

    /**
     * @notice View the amount of dividend in wei that an address has withdrawn.
     * @param account The address of a token holder.
     * @return The amount of dividend in wei that `account` has withdrawn.
     */
    function withdrawnDividendOf(address account) public view returns (uint256) {
        return s_withdrawnDividends[account];
    }

    /**
     * @notice View the amount of dividend in wei that an address has earned in total.
     * @dev accumulativeDividendOf(account) = withdrawableDividendOf(account) + withdrawnDividendOf(account)
     * = (magnifiedDividendPerShare * balanceOf(account) + magnifiedDividendCorrections[account]) / magnitude
     * @param account The address of a token holder.
     * @return The amount of dividend in wei that `account` has earned in total.
     */
    function accumulativeDividendOf(address account) public view returns (uint256) {
        return s_magnifiedDividendPerShare * IERC20(address(s_rayFiToken)).balanceOf(account) / MAGNITUDE;
    }

    /**
     * @notice View the amount of Prisma an address has earned from staking
     */
    function distributeEarnedPrisma(address account) public view returns (uint256) {
        uint256 _userStakedPrisma = s_rayFiToken.getStakedBalance(account);
        uint256 _prismaDividend = (s_magnifiedPrismaPerShare * _userStakedPrisma) / MAGNITUDE;
        return _prismaDividend;
    }

    //////////////////////////
    // Private Functions    //
    //////////////////////////

    /**
     * @notice Processes dividends for all token holders
     */
    function _process(uint256 gasForDividends, bool isReinvesting) private {
        uint256 startingGas = gasleft();
        if (startingGas < gasForDividends) {
            revert RayFiDividendTracker__InsufficientGas();
        }

        address[] memory shareholders = s_rayFiToken.getShareholders();

        uint256 shareholderCount = shareholders.length;
        if (shareholders.length == 0) {
            revert RayFiDividendTracker__ZeroShareholders();
        }

        uint256 gasUsed;
        uint256 lastProcessedIndex = s_lastProcessedIndex;
        while (gasUsed < gasForDividends) {
            if (isReinvesting) {
                _processReinvest(shareholders[lastProcessedIndex]);
            } else {
                _processAccount(shareholders[lastProcessedIndex]);
            }

            lastProcessedIndex++;
            if (lastProcessedIndex >= shareholderCount) {
                lastProcessedIndex = 0;
                break;
            }

            gasUsed += startingGas - gasleft();
        }

        s_lastProcessedIndex = lastProcessedIndex;
    }

    /**
     * @notice Processes dividends for an account
     */
    function _processAccount(address account) private {
        uint256 withdrawableDividend = withdrawableDividendOf(account)
            - (
                withdrawableDividendOf(account)
                    * ((s_rayFiToken.getStakedBalance(account) * MAGNITUDE) / IERC20(address(s_rayFiToken)).balanceOf(account))
            ) / MAGNITUDE;
        if (withdrawableDividend > 0) {
            _withdrawDividendOfUser(account, withdrawableDividend);
        }
    }

    /**
     * @notice Withdraws the stablecoins distributed to the sender.
     */
    function _withdrawDividendOfUser(address account, uint256 amount) private {
        uint256 _withdrawableDividend = withdrawableDividendOf(account);

        if (_withdrawableDividend > 0 && amount <= _withdrawableDividend) {
            s_withdrawnDividends[account] += amount;

            bool success = IERC20(s_dividendToken).transfer(account, amount);

            if (!success) {
                s_withdrawnDividends[account] = s_withdrawnDividends[account] - amount;
            }

            emit DividendsWithdrawn(account, amount);
        }
    }

    /**
     * @dev Internal function used to reinvest and compound all the dividends of Prisma stakers
     */
    function autoReinvest(uint256 gasForDividends) private {
        uint256 _totalStakedPrisma = s_rayFiToken.getTotalStakedAmount();
        uint256 _totalUnclaimedDividend = IERC20(s_dividendToken).balanceOf(address(this));
        if (_totalStakedPrisma > 10 && _totalUnclaimedDividend > 10) {
            s_processingAutoReinvest = true;
            IERC20(s_dividendToken).approve(address(s_router), _totalUnclaimedDividend);
            address[] memory path = new address[](2);
            path[0] = s_dividendToken;
            path[1] = address(s_rayFiToken);
            s_router.swapExactTokensForTokens(_totalUnclaimedDividend, 0, path, address(this), block.timestamp);

            uint256 _contractPrismaBalance = IERC20(address(s_rayFiToken)).balanceOf(address(this));
            s_magnifiedPrismaPerShare = (_contractPrismaBalance * MAGNITUDE) / _totalStakedPrisma;

            _process(gasForDividends, true);

            s_magnifiedPrismaPerShare = 0;

            s_processingAutoReinvest = false;

            s_totalDividendsDistributed += _totalUnclaimedDividend;
        }
    }

    /**
     * @dev Internal function used to compound Prisma for `account`
     */
    function _processReinvest(address account) private returns (bool) {
        uint256 _reinvestableDividend = withdrawableDividendOf(account);

        if (_reinvestableDividend > 0) {
            s_withdrawnDividends[account] += _reinvestableDividend;
            uint256 _prismaToCompound = distributeEarnedPrisma(account);
            s_rayFiToken.compound(account, _prismaToCompound);
            emit DividendsReinvested(account, _prismaToCompound, s_lastDistribution, false);
            return true;
        }
        return false;
    }
}
