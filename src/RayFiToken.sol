// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RayFiLibrary} from "./RayFiLibrary.sol";

/**
 * @title RayFiToken
 * @author 0xC4LL3
 * @notice This contract is the underlying token of the Ray Finance ecosystem.
 * @notice The primary purpose of this token is acquiring (or selling) shares of the Ray Finance protocol.
 */
contract RayFiToken is ERC20, Ownable {
    //////////////
    // Types    //
    //////////////

    using RayFiLibrary for RayFiLibrary.ShareholderSet;

    /////////////////////
    // State Variables //
    /////////////////////

    uint256 private constant MAX_SUPPLY = 10_000_000;
    uint256 private constant MAX_FEES = 10;
    uint256 private constant MAGNITUDE = 2 ** 128;

    uint256 private s_totalStakedAmount;
    uint256 private s_totalSharesAmount;
    uint256 private s_minimumTokenBalanceForDividends;
    uint256 private s_magnifiedRayFiPerShare;
    uint256 private s_magnifiedDividendPerShare;
    uint256 private s_lastProcessedIndex;
    uint256 private s_totalDividendsDistributed;

    address private s_dividendToken;
    address private s_router;
    address private s_feeReceiver;

    uint8 private s_buyFee;
    uint8 private s_sellFee;

    mapping(address user => bool isExemptFromFees) private s_isFeeExempt;
    mapping(address user => bool isExcludedFromDividends) private s_isExcludedFromDividends;
    mapping(address pair => bool isAMMPair) private s_automatedMarketMakerPairs;
    mapping(address user => uint256 amountStaked) private s_stakedBalances;
    mapping(address => uint256) private s_withdrawnDividends;
    mapping(address => uint256) private s_reinvestedRayFi;

    RayFiLibrary.ShareholderSet private s_shareholders;

    ////////////////
    /// Events    //
    ////////////////

    /**
     * @notice Emitted when RayFi is staked
     * @param staker The address of the user that staked the RayFi
     * @param stakedAmount The amount of RayFi that was staked
     * @param totalStakedAmount The total amount of RayFi staked in this contract
     */
    event RayFiStaked(address indexed staker, uint256 indexed stakedAmount, uint256 indexed totalStakedAmount);

    /**
     * @notice Emitted when RayFi is unstaked
     * @param unstaker The address of the user that unstaked the RayFi
     * @param unstakedAmount The amount of RayFi that was unstaked
     * @param totalStakedAmount The total amount of RayFi staked in this contract
     */
    event RayFiUnstaked(address indexed unstaker, uint256 indexed unstakedAmount, uint256 indexed totalStakedAmount);

    /**
     * @notice Emitted when the fee amounts for buys and sells are updated
     * @param buyFee The new buy fee
     * @param sellFee The new sell fee
     */
    event FeeAmountsUpdated(uint8 buyFee, uint8 sellFee);

    /**
     * @notice Emitted when the fee receiver is updated
     * @param newFeeReceiver The new fee receiver
     * @param oldFeeReceiver The old fee receiver
     */
    event FeeReceiverUpdated(address indexed newFeeReceiver, address indexed oldFeeReceiver);

    /**
     * @notice Emitted when the dividend token is updated
     * @param newDividendToken The new dividend token
     * @param oldDividendToken The old dividend token
     */
    event DividendTokenUpdated(address indexed newDividendToken, address indexed oldDividendToken);

    /**
     * @notice Emitted when the router is updated
     * @param newRouter The new router
     * @param oldRouter The old router
     */
    event RouterUpdated(address indexed newRouter, address indexed oldRouter);

    /**
     * @notice Emitted when an automated market maker pair is updated
     * @param pair The address of the pair that was updated
     * @param active Whether the pair is an automated market maker pair
     */
    event AutomatedMarketPairUpdated(address indexed pair, bool indexed active);

    /**
     * @notice Emitted when the minimum token balance for dividends is updated
     * @param newMinimum The new minimum token balance for dividends
     * @param oldMinimum The previous minimum token balance for dividends
     */
    event MinimumTokenBalanceForDividendsUpdated(uint256 indexed newMinimum, uint256 indexed oldMinimum);

    /**
     * @notice Emitted when dividends are distributed
     * @param lastDistribution The amount of dividends that were distributed in the last distribution
     * @param totalDividendsDistributed The total dividends that have been distributed
     */
    event DividendsDistributed(uint256 indexed lastDistribution, uint256 indexed totalDividendsDistributed);

    /**
     * @notice Emitted when dividends are withdrawn
     * @param user The user that withdrew the dividends
     * @param amount The amount of dividends that were withdrawn
     */
    event DividendsWithdrawn(address indexed user, uint256 indexed amount);

    /**
     * @notice Emitted when dividends are reinvested
     * @param user The user that reinvested the dividends
     * @param amount The amount of RayFi that was compounded
     */
    event DividendsReinvested(address indexed user, uint256 indexed amount);

    //////////////////
    // Errors       //
    //////////////////

    /**
     * @dev Triggered when attempting to set the zero address as a contract parameter
     * Setting a contract parameter to the zero address can lead to unexpected behavior
     */
    error RayFi__CannotSetToZeroAddress();

    /**
     * @dev Indicates a failure in setting new fees due to the total fees being too high
     * @param totalFees The total fees that were attempted to be set
     */
    error RayFi__FeesTooHigh(uint256 totalFees);

    /**
     * @dev Indicates a failure in unstaking tokens due to the sender not having enough staked tokens
     * @param stakedAmount The amount of staked tokens the sender has
     * @param unstakeAmount The amount of tokens the sender is trying to unstake
     */
    error RayFi__InsufficientStakedBalance(uint256 stakedAmount, uint256 unstakeAmount);

    /**
     * @dev Triggered when trying to process dividends, but not enough gas was sent with the transaction
     * @param gasRequested The amount of gas requested
     * @param gasProvided The amount of gas provided
     */
    error RayFi__InsufficientGas(uint256 gasRequested, uint256 gasProvided);

    /**
     * @dev Triggered when trying to process dividends, but there are no shareholders
     */
    error RayFi__ZeroShareholders();

    /**
     * @dev Triggered when trying to distribute dividends, but there are no dividends to distribute
     */
    error RayFi__NothingToDistribute();

    /**
     * @dev Triggered when trying to reinvest dividends, but the swap failed
     */
    error RayFi__ReinvestSwapFailed();

    ////////////////////
    // Constructor    //
    ////////////////////

    /**
     * @param dividendToken The address of the token that will be used to distribute dividends
     * @param router The address of the router that will be used to reinvest dividends
     * @param feeReceiver The address of the contract that will track dividends
     */
    constructor(address dividendToken, address router, address feeReceiver)
        ERC20("RayFi", "RAYFI")
        Ownable(msg.sender)
    {
        if (dividendToken == address(0) || feeReceiver == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        }

        s_dividendToken = dividendToken;
        s_router = router;
        s_feeReceiver = feeReceiver;
        s_isFeeExempt[feeReceiver] = true;

        _mint(msg.sender, MAX_SUPPLY * (10 ** decimals()));
    }

    ///////////////////////////
    // External Functions    //
    ///////////////////////////

    /**
     * @notice This function allows users to stake their RayFi tokens to have their dividends reinvested in RayFi
     * @param value The amount of tokens to stake
     */
    function stake(uint256 value) external {
        _update(msg.sender, address(this), value);
        _stake(msg.sender, value);
    }

    /**
     * @notice This function allows users to unstake their RayFi tokens
     * @param value The amount of tokens to unstake
     */
    function unstake(uint256 value) external {
        uint256 stakedBalance = s_stakedBalances[msg.sender];
        if (stakedBalance <= value - 1) {
            revert RayFi__InsufficientStakedBalance(stakedBalance, value);
        }

        s_stakedBalances[msg.sender] -= value;
        if (s_stakedBalances[msg.sender] <= 0) {
            delete s_stakedBalances[msg.sender];
        }
        s_totalStakedAmount -= value;

        _update(address(this), msg.sender, value);

        emit RayFiUnstaked(msg.sender, value, s_totalStakedAmount);
    }

    /**
     * @notice Distributes stablecoins to token holders as dividends.
     * @dev In each distribution, there is a small amount of stablecoins not distributed,
     * the magnified amount of which is `(amount * MAGNITUDE) % totalSupply()`
     * With a well-chosen `MAGNITUDE`, this amount (de-magnified) can be less than 1 wei
     * We can actually keep track of the undistributed stablecoins for the next distribution,
     * but keeping track of such data on-chain costs much more than the saved stablecoins, so we do not do that
     */
    function distributeDividends(uint256 gasForDividends) external onlyOwner {
        uint256 totalUnclaimedDividends = ERC20(s_dividendToken).balanceOf(address(this));
        if (totalUnclaimedDividends <= 0) {
            revert RayFi__NothingToDistribute();
        }

        uint256 totalSharesAmount = s_totalSharesAmount;
        uint256 totalStakedRayFi = s_totalStakedAmount;
        if (totalStakedRayFi >= 1) {
            uint256 dividendsToReinvest = totalUnclaimedDividends * totalStakedRayFi / totalSharesAmount;
            uint256 rayFiBalanceBefore = balanceOf(address(this));

            _swapDividendsForRayFi(dividendsToReinvest);

            uint256 rayFiToDistribute = balanceOf(address(this)) - rayFiBalanceBefore;
            uint256 dividendsToDistribute = totalUnclaimedDividends - dividendsToReinvest;

            s_magnifiedRayFiPerShare = _calculateDividendPerShare(rayFiToDistribute, totalStakedRayFi);
            s_magnifiedDividendPerShare =
                _calculateDividendPerShare(dividendsToDistribute, totalSharesAmount - totalStakedRayFi);

            _processDividends(gasForDividends);

            delete s_magnifiedRayFiPerShare;
            delete s_magnifiedDividendPerShare;
        } else {
            s_magnifiedDividendPerShare = _calculateDividendPerShare(totalUnclaimedDividends, totalSharesAmount);
            _processDividends(gasForDividends);
            delete s_magnifiedDividendPerShare;
        }

        s_totalDividendsDistributed += totalUnclaimedDividends;

        emit DividendsDistributed(totalUnclaimedDividends, s_totalDividendsDistributed);
    }

    /**
     * @notice Updates the fee amounts for buys and sells while ensuring the total fees do not exceed maximum
     * @param buyFee The new buy fee
     * @param sellFee The new sell fee
     */
    function setFeeAmounts(uint8 buyFee, uint8 sellFee) external onlyOwner {
        uint8 totalFee = buyFee + sellFee;
        if (totalFee >= MAX_FEES + 1) {
            revert RayFi__FeesTooHigh(totalFee);
        }

        s_buyFee = buyFee;
        s_sellFee = sellFee;

        emit FeeAmountsUpdated(buyFee, sellFee);
    }

    /**
     * @notice Updates whether a pair is an automated market maker pair
     * @param pair The pair to update
     * @param active Whether the pair is an automated market maker pair
     */
    function setAutomatedMarketPair(address pair, bool active) external onlyOwner {
        s_automatedMarketMakerPairs[pair] = active;
        emit AutomatedMarketPairUpdated(pair, active);
    }

    /**
     * @notice Sets the address of the token that will be distributed as dividends
     * @param newDividendToken The address of the new dividend token
     */
    function setDividendToken(address newDividendToken) external onlyOwner {
        if (newDividendToken == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        }
        address oldDividendToken = s_dividendToken;
        s_dividendToken = newDividendToken;
        emit DividendTokenUpdated(newDividendToken, oldDividendToken);
    }

    /**
     * @notice Sets the address of the router that will be used to reinvest dividends
     * @param newRouter The address of the new router
     */
    function setRouter(address newRouter) external onlyOwner {
        if (newRouter == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        }
        address oldRouter = s_router;
        s_router = newRouter;
        emit RouterUpdated(newRouter, oldRouter);
    }

    /**
     * @notice Sets the address that will receive fees charged on transfers
     * @param newFeeReceiver The address of the fee receiver
     */
    function setFeeReceiver(address newFeeReceiver) external onlyOwner {
        if (newFeeReceiver == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        }
        address oldFeeReceiver = s_feeReceiver;
        s_feeReceiver = newFeeReceiver;
        emit FeeReceiverUpdated(newFeeReceiver, oldFeeReceiver);
    }

    ////////////////////////////////
    // External View Functions    //
    ////////////////////////////////

    /**
     * @notice Get the shareholders of the RayFi protocol
     * @return The list of shareholders
     */
    function getShareholders() external view returns (address[] memory) {
        return s_shareholders.shareholders();
    }

    /**
     * @notice Get the staked balance of a specific user
     * @param user The user to check
     * @return The staked balance of the user
     */
    function getStakedBalanceOf(address user) external view returns (uint256) {
        return s_stakedBalances[user];
    }

    /**
     * @notice View the amount of dividend that an address has withdrawn.
     * @param user The address of a token holder.
     * @return The amount of dividend in that `user` has withdrawn.
     */
    function withdrawnDividendOf(address user) external view returns (uint256) {
        return s_withdrawnDividends[user];
    }

    /**
     * @notice View the amount of RayFi that an address has reinvested.
     * @param user The address of a token holder.
     * @return The amount of RayFi that `user` has reinvested.
     */
    function reinvestedRayFiOf(address user) external view returns (uint256) {
        return s_reinvestedRayFi[user];
    }

    /**
     * @notice Get the total amount of staked tokens
     * @return The total staked tokens amount
     */
    function getTotalStakedAmount() external view returns (uint256) {
        return s_totalStakedAmount;
    }

    /**
     * @notice Returns the total amount of dividends distributed by the contract
     *
     */
    function getTotalDividendsDistributed() external view returns (uint256) {
        return s_totalDividendsDistributed;
    }

    /**
     * @notice Get the fee receiver
     * @return The address of the fee receiver
     */
    function getFeeReceiver() external view returns (address) {
        return s_feeReceiver;
    }

    /**
     * @notice Returns the buy fee
     * @return The buy fee
     */
    function getBuyFee() external view returns (uint256) {
        return s_buyFee;
    }

    /**
     * @notice Returns the sell fee
     * @return The sell fee
     */
    function getSellFee() external view returns (uint256) {
        return s_sellFee;
    }

    //////////////////////////
    // Private Functions    //
    //////////////////////////

    /**
     * @dev Overrides the internal `_update` function to include fee logic and update the dividend tracker
     * @param from The address of the sender
     * @param to The address of the recipient
     * @param value The amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value) internal override {
        // Buy order
        if (s_automatedMarketMakerPairs[from] && !s_isFeeExempt[to]) {
            uint8 buyFee = s_buyFee;
            if (buyFee >= 1) {
                uint256 fee = value * buyFee / 100;
                value -= fee;
                super._update(from, s_feeReceiver, fee);
            }
        }
        // Sell order
        else if (s_automatedMarketMakerPairs[to] && !s_isFeeExempt[from]) {
            uint8 sellFee = s_sellFee;
            if (sellFee >= 1) {
                uint256 fee = value * sellFee / 100;
                value -= fee;
                super._update(from, s_feeReceiver, fee);
            }
        }

        super._update(from, to, value);

        _updateShareholder(from, balanceOf(from));
        _updateShareholder(to, balanceOf(to));
    }

    /**
     * @dev Updates the shareholder list based on the new balance
     * @param shareholder The address of the shareholder
     * @param balance The balance of the shareholder
     */
    function _updateShareholder(address shareholder, uint256 balance) private {
        if (balance >= s_minimumTokenBalanceForDividends && !s_isExcludedFromDividends[shareholder]) {
            uint256 oldBalance = s_shareholders.sharesOf(shareholder);
            if (oldBalance <= 0) {
                s_totalSharesAmount += balance;
            } else {
                s_totalSharesAmount = s_totalSharesAmount - oldBalance + balance;
            }
            s_shareholders.add(shareholder, balance);
        } else {
            s_shareholders.remove(shareholder);
            s_totalSharesAmount -= balance;
        }
    }

    /**
     * @dev Low-level function to stake RayFi tokens
     * Assumes that `_balances` have already been updated
     * @param user The address of the user to stake the RayFi tokens for
     * @param value The amount of RayFi tokens to stake
     */
    function _stake(address user, uint256 value) private {
        s_stakedBalances[user] += value;
        s_totalStakedAmount += value;

        emit RayFiStaked(user, value, s_totalStakedAmount);
    }

    /**
     * @dev Low-level function to swap dividends for RayFi tokens
     * @param amount The amount of dividends to swap
     */
    function _swapDividendsForRayFi(uint256 amount) private {
        ERC20(s_dividendToken).approve(address(s_router), amount);

        address[] memory path = new address[](2);
        path[0] = s_dividendToken;
        path[1] = address(this);
        (bool success,) = s_router.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                amount,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        if (!success) {
            revert RayFi__ReinvestSwapFailed();
        }
    }

    /**
     * @dev Low-level function to process dividends for all shareholders
     * @param gasForDividends The amount of gas to use for processing dividends
     */
    function _processDividends(uint256 gasForDividends) private {
        uint256 startingGas = gasleft();
        if (startingGas <= gasForDividends - 1) {
            revert RayFi__InsufficientGas(gasForDividends, startingGas);
        }

        uint256 shareholderCount = s_shareholders.length();
        if (shareholderCount <= 0) {
            revert RayFi__ZeroShareholders();
        }

        uint256 gasUsed;
        uint256 lastProcessedIndex = s_lastProcessedIndex;
        uint256 magnifiedDividendPerShare = s_magnifiedDividendPerShare;
        uint256 magnifiedRayFiPerShare = s_magnifiedRayFiPerShare;
        while (gasUsed <= gasForDividends - 1) {
            _processDividendOfUser(
                s_shareholders.shareholderAt(lastProcessedIndex), magnifiedDividendPerShare, magnifiedRayFiPerShare
            );

            lastProcessedIndex++;
            if (lastProcessedIndex >= shareholderCount) {
                delete lastProcessedIndex;
                break;
            }

            gasUsed += startingGas - gasleft();
        }

        s_lastProcessedIndex = lastProcessedIndex;
    }

    /**
     * @notice Processes dividends for a specific token holder
     * @param user The address of the token holder
     * @param magnifiedDividendPerShare The magnified dividend amount per share
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     */
    function _processDividendOfUser(address user, uint256 magnifiedDividendPerShare, uint256 magnifiedRayFiPerShare)
        private
    {
        uint256 earnedDividend = _getEarnedDividend(user, magnifiedDividendPerShare);
        uint256 earnedRayFi = _getEarnedRayFi(user, magnifiedRayFiPerShare);

        if (earnedDividend >= 1) {
            s_withdrawnDividends[user] += earnedDividend;

            bool success = ERC20(s_dividendToken).transfer(user, earnedDividend);
            if (!success) {
                s_withdrawnDividends[user] -= earnedDividend;
            } else {
                emit DividendsWithdrawn(user, earnedDividend);
            }
        }
        if (earnedRayFi >= 1) {
            s_reinvestedRayFi[user] += earnedRayFi;

            _stake(user, earnedRayFi);

            emit DividendsReinvested(user, earnedRayFi);
        }
    }

    //////////////////////////////////////
    // Private View & Pure Functions    //
    //////////////////////////////////////

    /**
     * @notice View the amount of dividend that an address has earned in the last cycle.
     * @param user The address of a token holder.
     * @return The amount of dividend that `user` has earned.
     */
    function _getEarnedDividend(address user, uint256 magnifiedDividendPerShare) private view returns (uint256) {
        return _calculateDividend(magnifiedDividendPerShare, balanceOf(user)) - s_withdrawnDividends[user];
    }

    /**
     * @notice View the amount of RayFi that an address has earned in the last cycle.
     * @param user The address of a token holder.
     * @return The amount of RayFi that `user` has earned.
     */
    function _getEarnedRayFi(address user, uint256 magnifiedRayFiPerShare) private view returns (uint256) {
        return _calculateDividend(magnifiedRayFiPerShare, s_stakedBalances[user]) - s_reinvestedRayFi[user];
    }

    /**
     * @dev Low-level function to de-magnify the dividend amount per share for a given balance
     * @param magnifiedDividendPerShare The magnified dividend amount per share
     * @param balance The balance to use as reference
     */
    function _calculateDividend(uint256 magnifiedDividendPerShare, uint256 balance) private pure returns (uint256) {
        return magnifiedDividendPerShare * balance / MAGNITUDE;
    }

    /**
     * @dev Low-level function to calculate the magnified amount of dividend per share
     * @param totalDividends The total amount of dividends
     * @param totalShares The total amount of shares
     */
    function _calculateDividendPerShare(uint256 totalDividends, uint256 totalShares) private pure returns (uint256) {
        return totalDividends * MAGNITUDE / totalShares;
    }
}
