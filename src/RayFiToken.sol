// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IterableMapping} from "./IterableMapping.sol";
import {IRayFiToken} from "./IRayFiToken.sol";

/**
 * @title RayFiToken
 * @author 0xC4LL3
 * @notice This contract is the underlying token of the Ray Finance ecosystem.
 * @notice The primary purpose of this token is acquiring (or selling) shares of the Ray Finance protocol.
 */
contract RayFiToken is ERC20, Ownable, IRayFiToken {
    //////////////
    // Types    //
    //////////////

    using IterableMapping for IterableMapping.Map;

    /////////////////////
    // State Variables //
    /////////////////////

    uint256 private constant MAX_SUPPLY = 10_000_000 * (10 ** 18);
    uint256 private constant MAX_FEES = 10;
    uint256 private constant INTERNAL_TRANSACTION_OFF = 1;
    uint256 private constant INTERNAL_TRANSACTION_ON = 2;

    IterableMapping.Map private s_shareholders;

    address private s_dividendTracker;

    mapping(address user => bool isExemptFromFees) private s_isFeeExempt;
    mapping(address user => bool isExcludedFromDividends) private s_isExcludedFromDividends;
    mapping(address pair => bool isAMMPair) private s_automatedMarketMakerPairs;
    mapping(address user => uint256 amountStaked) private s_stakedBalances;

    uint256 private s_totalStakedAmount;
    uint256 private s_minSwapFees;
    uint256 private s_minimumTokenBalanceForDividends;
    uint256 private s_buyLiquidityFee;
    uint256 private s_buyTreasuryFee;
    uint256 private s_buyRayFundFee;
    uint256 private s_sellLiquidityFee;
    uint256 private s_sellTreasuryFee;
    uint256 private s_sellRayFundFee;
    uint256 private s_internalTransactionStatus;

    ////////////////
    /// Events    //
    ////////////////

    /**
     * @notice Emitted when RayFi is staked
     * @param staker The address of the account that staked the RayFi
     * @param stakedAmount The amount of RayFi that was staked
     * @param totalStakedAmount The total amount of RayFi staked in this contract
     */
    event RayFiStaked(address indexed staker, uint256 indexed stakedAmount, uint256 indexed totalStakedAmount);

    /**
     * @notice Emitted when RayFi is unstaked
     * @param unstaker The address of the account that unstaked the RayFi
     * @param unstakedAmount The amount of RayFi that was unstaked
     * @param totalStakedAmount The total amount of RayFi staked in this contract
     */
    event RayFiUnstaked(address indexed unstaker, uint256 indexed unstakedAmount, uint256 indexed totalStakedAmount);

    /**
     * @notice Emitted when the fee amounts for buys and sells are updated
     * @param buyLiquidityFee The new buy liquidity fee
     * @param buyTreasuryFee The new buy treasury fee
     * @param buyRayFundFee The new buy RAY fund fee
     * @param sellLiquidityFee The new sell liquidity fee
     * @param sellTreasuryFee The new sell treasury fee
     * @param sellRayFundFee The new sell RAY fund fee
     */
    event FeeAmountsUpdated(
        uint256 buyLiquidityFee,
        uint256 buyTreasuryFee,
        uint256 buyRayFundFee,
        uint256 sellLiquidityFee,
        uint256 sellTreasuryFee,
        uint256 sellRayFundFee
    );

    /**
     * @notice Emitted when the minimum swap fees for conversion to stablecoin are updated
     * @param newMin The new minimum swap fees
     * @param oldMin The previous minimum swap fees
     */
    event MinSwapFeesUpdated(uint256 indexed newMin, uint256 indexed oldMin);

    /**
     * @notice Emitted when an automated market maker pair is updated
     * @param pair The address of the pair that was updated
     * @param active Whether the pair is an automated market maker pair
     */
    event AutomatedMarketPairUpdated(address indexed pair, bool indexed active);

    //////////////////
    // Errors       //
    //////////////////

    /**
     * @dev Triggered when attempting to set the zero address as a contract parameter
     * Setting a contract parameter to the zero address can lead to unexpected behavior
     */
    error RayFi__CannotSetToZeroAddress();

    /**
     * @dev Indicates a failure in setting new fees,
     * due to the total fees being too high
     * @param totalFees The total fees that were attempted to be set
     */
    error RayFi__FeesTooHigh(uint256 totalFees);

    /**
     * @dev Indicates a failure in unstaking tokens,
     * due to the sender not having enough staked tokens
     * @param stakedAmount The amount of staked tokens the sender has
     * @param unstakeAmount The amount of tokens the sender is trying to unstake
     */
    error RayFi__InsufficientStakedBalance(uint256 stakedAmount, uint256 unstakeAmount);

    /**
     * @dev Indicates a failure in compounding RayFi tokens,
     * due to the caller not being the RayFi Dividend Tracker
     * @param caller The address of the caller
     */
    error RayFi__InvalidCompoundCaller(address caller);

    /**
     * @dev Indicates a failure in swapping fees,
     * due to the call to the Dividend Tracker failing
     */
    error RayFi__FailedToSwapFees();

    ////////////////////
    // Constructor    //
    ////////////////////

    /**
     * @param dividendTracker The address of the contract that will track dividends
     * @param minSwapFees The minimum amount of fees required to swap to stablecoin
     */
    constructor(address dividendTracker, uint256 minSwapFees) ERC20("RayFi", "RAYFI") Ownable(msg.sender) {
        if (dividendTracker == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        }

        s_dividendTracker = dividendTracker;

        s_minSwapFees = minSwapFees * (10 ** decimals());
        s_isFeeExempt[dividendTracker] = true;

        _mint(msg.sender, MAX_SUPPLY * (10 ** decimals()));
    }

    ///////////////////////////
    // External Functions    //
    ///////////////////////////

    /**
     * @notice This functions allows users to stake their RayFi tokens in order to have their dividends compounded
     * @param value The amount of tokens to stake
     */
    function stake(uint256 value) external {
        _update(msg.sender, address(this), value);
        _stake(msg.sender, value);
    }

    /**
     * @notice This functions allows users to unstake their RayFi tokens
     * @param value The amount of tokens to unstake
     */
    function unstake(uint256 value) external {
        uint256 stakedBalance = s_stakedBalances[msg.sender];
        if (stakedBalance < value) {
            revert RayFi__InsufficientStakedBalance(stakedBalance, value);
        }

        s_stakedBalances[msg.sender] -= value;
        if (s_stakedBalances[msg.sender] == 0) {
            delete s_stakedBalances[msg.sender];
        }
        s_totalStakedAmount -= value;

        _update(address(this), msg.sender, value);

        emit RayFiUnstaked(msg.sender, value, s_totalStakedAmount);
    }

    /**
     * @notice This function is called by the dividend tracker to compound the RayFi tokens for a user
     * @dev Compounding intentionally bypasses buy fees
     * @param user The address of the user to compound the RayFi tokens for
     * @param value The amount of RayFi tokens to compound
     */
    function compound(address user, uint256 value) external {
        if (msg.sender != s_dividendTracker) {
            revert RayFi__InvalidCompoundCaller(msg.sender);
        }
        _update(msg.sender, address(this), value);
        _stake(user, value);
    }

    /**
     * @notice Updates the fee amounts for buys and sells while ensuring the total fees do not exceed maximum
     * @param buyLiquidityFee The percentage of the buy fee that goes to the liquidity pool
     * @param buyTreasuryFee The percentage of the buy fee that goes to the treasury
     * @param buyRayFundFee The percentage of the buy fee that goes to the RAY fund
     * @param sellLiquidityFee The percentage of the sell fee that goes to the liquidity pool
     * @param sellTreasuryFee The percentage of the sell fee that goes to the treasury
     * @param sellRayFundFee The percentage of the sell fee that goes to the RAY fund
     */
    function setFeeAmounts(
        uint256 buyLiquidityFee,
        uint256 buyTreasuryFee,
        uint256 buyRayFundFee,
        uint256 sellLiquidityFee,
        uint256 sellTreasuryFee,
        uint256 sellRayFundFee
    ) external onlyOwner {
        uint256 totalFees =
            buyLiquidityFee + buyTreasuryFee + buyRayFundFee + sellLiquidityFee + sellTreasuryFee + sellRayFundFee;
        if (totalFees > MAX_FEES) {
            revert RayFi__FeesTooHigh(totalFees);
        }

        s_buyLiquidityFee = buyLiquidityFee;
        s_buyTreasuryFee = buyTreasuryFee;
        s_buyRayFundFee = buyRayFundFee;
        s_sellLiquidityFee = sellLiquidityFee;
        s_sellTreasuryFee = sellTreasuryFee;
        s_sellRayFundFee = sellRayFundFee;

        emit FeeAmountsUpdated(
            buyLiquidityFee, buyTreasuryFee, buyRayFundFee, sellLiquidityFee, sellTreasuryFee, sellRayFundFee
        );
    }

    /**
     * @notice Changes the minimum swap fees for conversion to stablecoin to a new value
     * @dev Can only be called by the owner
     * @param newValue The new value for the minimum swap fees
     */
    function setMinSwapFees(uint256 newValue) external onlyOwner {
        uint256 oldValue = s_minSwapFees;
        s_minSwapFees = newValue;
        emit MinSwapFeesUpdated(newValue, oldValue);
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
     * @notice Updates the Dividend Tracker to a new address, excluding it and this contract from dividends
     * @param dividendTracker The new address for the Dividend Tracker
     */
    function setDividendTracker(address dividendTracker) external onlyOwner {
        if (dividendTracker == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        }
        s_dividendTracker = dividendTracker;
    }

    /////////////////////////////////////////
    // External & Public View Functions    //
    /////////////////////////////////////////

    /**
     * @notice Get the shareholders of the RayFi protocol
     * @dev This function is used by the Dividend Tracker to distribute dividends
     * It is a known limitation that this function will revert if the shareholder array becomes too large
     * This limitation only applies when the function is called by a contract, since it will be free otherwise
     * @return The list of shareholders
     */
    function getShareholders() external view returns (address[] memory) {
        return s_shareholders.keys();
    }

    /**
     * @notice Get the staked balance of a specific user
     * @param user The user to check
     * @return The staked balance of the user
     */
    function getStakedBalance(address user) external view returns (uint256) {
        return s_stakedBalances[user];
    }

    /**
     * @notice Get the total amount of staked tokens
     * @return The total staked tokens amount
     */
    function getTotalStakedAmount() external view returns (uint256) {
        return s_totalStakedAmount;
    }

    /**
     * @notice Get the Dividend Tracker
     * @return The address of the Dividend Tracker
     */
    function getDividendTracker() external view returns (address) {
        return s_dividendTracker;
    }

    /**
     * @notice Get the minimum swap fees for conversion to stablecoin
     * @return The minimum swap fees
     */
    function getMinSwapFees() external view returns (uint256) {
        return s_minSwapFees;
    }

    /**
     * @notice Get the fee amounts for buys and sells
     * @return buyLiquidityFee The percentage of the buy fee that goes to the liquidity pool
     * @return buyTreasuryFee The percentage of the buy fee that goes to the treasury
     * @return buyRayFundFee The percentage of the buy fee that goes to the RAY fund
     * @return sellLiquidityFee The percentage of the sell fee that goes to the liquidity pool
     * @return sellTreasuryFee The percentage of the sell fee that goes to the treasury
     * @return sellRayFundFee The percentage of the sell fee that goes to the RAY fund
     */
    function getFeeAmounts()
        external
        view
        returns (
            uint256 buyLiquidityFee,
            uint256 buyTreasuryFee,
            uint256 buyRayFundFee,
            uint256 sellLiquidityFee,
            uint256 sellTreasuryFee,
            uint256 sellRayFundFee
        )
    {
        return (
            s_buyLiquidityFee,
            s_buyTreasuryFee,
            s_buyRayFundFee,
            s_sellLiquidityFee,
            s_sellTreasuryFee,
            s_sellRayFundFee
        );
    }

    /**
     * @notice Returns the total buy fees, which is the sum of liquidity fee, treasury fee and RAY fund fee for buys
     * @return The total buy fees
     */
    function getTotalBuyFees() public view returns (uint256) {
        return s_buyLiquidityFee + s_buyTreasuryFee + s_buyRayFundFee;
    }

    /**
     * @notice Returns the total sell fees, which is the sum of liquidity fee, treasury fee and RAY fund fee for sells
     * @return The total sell fees
     */
    function getTotalSellFees() public view returns (uint256) {
        return s_sellLiquidityFee + s_sellTreasuryFee + s_sellRayFundFee;
    }

    /////////////////////////////////////
    // Internal & Private Functions    //
    /////////////////////////////////////

    /**
     * @dev Overrides the internal `_update` function to include fee logic and update the dividend tracker
     * @param from The address of the sender
     * @param to The address of the recipient
     * @param value The amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value) internal override {
        if (s_internalTransactionStatus != INTERNAL_TRANSACTION_ON) {
            // Buy order
            if (s_automatedMarketMakerPairs[from] && !s_isFeeExempt[to]) {
                uint256 totalBuyFees = getTotalBuyFees();
                if (totalBuyFees > 0) {
                    uint256 fee = (value * totalBuyFees) / 100;
                    value -= fee;
                    super._update(from, s_dividendTracker, fee);
                }
            }
            // Sell order
            else if (s_automatedMarketMakerPairs[to] && !s_isFeeExempt[from]) {
                uint256 totalSellFees = getTotalSellFees();
                if (totalSellFees > 0) {
                    uint256 fee = (value * totalSellFees) / 100;
                    value -= fee;
                    super._update(from, s_dividendTracker, fee);
                }

                if (balanceOf(s_dividendTracker) >= s_minSwapFees) {
                    s_internalTransactionStatus = INTERNAL_TRANSACTION_ON;
                    (bool success,) = s_dividendTracker.call(abi.encodeWithSignature("swapFees()"));
                    if (!success) {
                        revert RayFi__FailedToSwapFees();
                    }
                    s_internalTransactionStatus = INTERNAL_TRANSACTION_OFF;
                }
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
            s_shareholders.set(shareholder, balance);
        } else {
            s_shareholders.remove(shareholder);
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
}
