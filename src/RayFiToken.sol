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
    address private s_dividendReceiver;

    uint8 private s_buyFee;
    uint8 private s_sellFee;

    mapping(address user => bool isExemptFromFees) private s_isFeeExempt;
    mapping(address user => bool isExcludedFromDividends) private s_isExcludedFromDividends;
    mapping(address pair => bool isAMMPair) private s_automatedMarketMakerPairs;
    mapping(address user => uint256 amountStaked) private s_stakedBalances;

    RayFiLibrary.ShareholderSet private s_shareholders;
    RayFiLibrary.ShareholderSet[] private s_shareholdersSnapshots;

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
     * @notice Emitted when a user is marked as exempt from fees
     * @param user The address of the user
     * @param isExempt Whether the user is exempt from fees
     */
    event IsUserExemptFromFeesUpdated(address indexed user, bool indexed isExempt);

    /**
     * @notice Emitted when the fee receiver is updated
     * @param newFeeReceiver The new fee receiver
     * @param oldFeeReceiver The old fee receiver
     */
    event FeeReceiverUpdated(address indexed newFeeReceiver, address indexed oldFeeReceiver);

    /**
     * @notice Emitted when the dividend receiver is updated
     * @param newDividendReceiver The new dividend receiver
     * @param oldDividendReceiver The old dividend receiver
     */
    event DividendReceiverUpdated(address indexed newDividendReceiver, address indexed oldDividendReceiver);

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
     * @notice Emitted when a user is marked as excluded from dividends
     * @param user The address of the user
     * @param isExcluded Whether the user is excluded from dividends
     */
    event IsUserExcludedFromDividendsUpdated(address indexed user, bool indexed isExcluded);

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
     * @notice Triggered when trying to send RayFi tokens to this contract
     * Users should call the `stake` function to stake their RayFi tokens
     * @dev Sending RayFi tokens to the contract is not allowed to prevent accidental staking
     * This also simplifies dividend tracking and distribution logic
     */
    error RayFi__CannotManuallySendRayFiTokensToTheContract();

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
     * @notice Indicates a failure in staking tokens due to the input amount being too low
     * @param tokenAmount The amount of tokens the sender is trying to stake
     * @param minimumTokenBalance The minimum amount of tokens required to stake
     */
    error RayFi__InsufficientTokensToStake(uint256 tokenAmount, uint256 minimumTokenBalance);

    /**
     * @dev Triggered when trying to process dividends, but not enough gas was sent with the transaction
     * @param gasRequested The amount of gas requested
     * @param gasProvided The amount of gas provided
     */
    error RayFi__InsufficientGas(uint256 gasRequested, uint256 gasProvided);

    /**
     * @dev Triggered when trying to process dividends without saving progress, but the distribution could not complete
     * @param shareholderCount The total number of shareholders
     * @param lastProcessedIndex The index of the last processed shareholder
     */
    error RayFi__StateLessDistributionCouldNotComplete(uint256 shareholderCount, uint256 lastProcessedIndex);

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
     * @param dividendReceiver The address of the wallet that will distribute swapped dividends
     */
    constructor(address dividendToken, address router, address feeReceiver, address dividendReceiver)
        ERC20("RayFi", "RAYFI")
        Ownable(msg.sender)
    {
        if (
            dividendToken == address(0) || router == address(0) || feeReceiver == address(0)
                || dividendReceiver == address(0)
        ) {
            revert RayFi__CannotSetToZeroAddress();
        }

        s_dividendToken = dividendToken;
        s_router = router;
        s_feeReceiver = feeReceiver;
        s_dividendReceiver = dividendReceiver;
        s_isFeeExempt[dividendReceiver] = true;
        s_isExcludedFromDividends[address(this)] = true;
        s_isExcludedFromDividends[address(0)] = true;

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
        uint256 minimumTokenBalanceForDividends = s_minimumTokenBalanceForDividends;
        value += s_stakedBalances[msg.sender];
        if (value <= minimumTokenBalanceForDividends - 1) {
            revert RayFi__InsufficientTokensToStake(value, minimumTokenBalanceForDividends);
        }

        super._update(msg.sender, address(this), value);
        _stake(msg.sender, value);
        _updateShareholder(msg.sender);
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

        _unstake(msg.sender, value);
        super._update(address(this), msg.sender, value);
        _updateShareholder(msg.sender);
    }

    /**
     * @notice High-level function to start the dividend distribution process in either stateful or stateless mode
     * The stateless mode is always the preferred one, as it is drastically more gas-efficient
     * The stateful mode is a backup to use only in case the stateless mode is unable to complete the distribution
     * Dividends are either sent to users as stablecoins or reinvested into RayFi for users who have staked their tokens
     * @dev In each distribution, there is a small amount of stablecoins not distributed,
     * the magnified amount of which is `(amount * MAGNITUDE) % totalSupply()`
     * With a well-chosen `MAGNITUDE`, this amount (de-magnified) can be less than 1 wei
     * We can actually keep track of the undistributed stablecoins for the next distribution,
     * but keeping track of such data on-chain costs much more than the saved stablecoins, so we do not do that
     */
    function distributeDividends(uint256 gasForDividends, bool isStateful) external onlyOwner {
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

            uint256 magnifiedDividendPerShare =
                _calculateDividendPerShare(dividendsToDistribute, totalSharesAmount - totalStakedRayFi);
            uint256 magnifiedRayFiPerShare = _calculateDividendPerShare(rayFiToDistribute, totalStakedRayFi);

            if (isStateful) {
                _snapshotShareholders();

                uint256 lastMagnifiedDividendPerShare = s_magnifiedDividendPerShare;
                uint256 lastMagnifiedRayFiPerShare = s_magnifiedRayFiPerShare;
                if (lastMagnifiedDividendPerShare >= 1 || lastMagnifiedRayFiPerShare >= 1) {
                    // Distribute the undistributed dividends from the last cycle
                    magnifiedDividendPerShare = lastMagnifiedDividendPerShare;
                    magnifiedRayFiPerShare = lastMagnifiedRayFiPerShare;
                } else {
                    s_magnifiedDividendPerShare = magnifiedRayFiPerShare;
                    s_magnifiedRayFiPerShare = magnifiedDividendPerShare;
                }
            }

            _processDividends(gasForDividends, magnifiedDividendPerShare, magnifiedRayFiPerShare, isStateful);
        } else {
            uint256 magnifiedDividendPerShare = _calculateDividendPerShare(totalUnclaimedDividends, totalSharesAmount);

            if (isStateful) {
                _snapshotShareholders();

                uint256 lastMagnifiedDividendPerShare = s_magnifiedDividendPerShare;
                if (lastMagnifiedDividendPerShare >= 1) {
                    // Distribute the undistributed dividends from the last cycle
                    magnifiedDividendPerShare = lastMagnifiedDividendPerShare;
                } else {
                    s_magnifiedDividendPerShare = magnifiedDividendPerShare;
                }
            }

            _processDividends(gasForDividends, magnifiedDividendPerShare, 0, isStateful);
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
     * @notice Sets whether a pair is an automated market maker pair for this token
     * @param pair The pair to update
     * @param isActive Whether the pair is an automated market maker pair
     */
    function setAutomatedMarketPair(address pair, bool isActive) external onlyOwner {
        s_automatedMarketMakerPairs[pair] = isActive;
        emit AutomatedMarketPairUpdated(pair, isActive);
    }

    /**
     * @notice Sets the minimum token balance for dividends
     * @param newMinimum The new minimum token balance for dividends
     */
    function setMinimumTokenBalanceForDividends(uint256 newMinimum) external onlyOwner {
        uint256 oldMinimum = s_minimumTokenBalanceForDividends;
        s_minimumTokenBalanceForDividends = newMinimum;
        emit MinimumTokenBalanceForDividendsUpdated(newMinimum, oldMinimum);
    }

    /**
     * @notice Sets whether an address is excluded from dividends
     * @param user The address to update
     * @param isExcluded Whether the address is excluded from dividends
     */
    function setIsExcludedFromDividends(address user, bool isExcluded) external onlyOwner {
        s_isExcludedFromDividends[user] = isExcluded;
        if (s_shareholders.contains(user)) {
            s_shareholders.remove(user);
            s_totalSharesAmount -= balanceOf(user);
        }
        emit IsUserExcludedFromDividendsUpdated(user, isExcluded);
    }

    /**
     * @notice Sets whether an address is exempt from fees
     * @param user The address to update
     * @param isExempt Whether the address is exempt from fees
     */
    function setFeeExempt(address user, bool isExempt) external onlyOwner {
        s_isFeeExempt[user] = isExempt;
        emit IsUserExemptFromFeesUpdated(user, isExempt);
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

    /**
     * @notice Sets the address of the wallet that will receive swapped dividends
     * @param newDividendReceiver The address of the new dividend receiver
     */
    function setDividendReceiver(address newDividendReceiver) external onlyOwner {
        if (newDividendReceiver == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        }
        address oldDividendReceiver = s_dividendReceiver;
        s_dividendReceiver = newDividendReceiver;
        emit DividendReceiverUpdated(newDividendReceiver, oldDividendReceiver);
    }

    ////////////////////////////////
    // External View Functions    //
    ////////////////////////////////

    /**
     * @notice Get the current shareholders of the RayFi protocol
     * @return The list of shareholders
     */
    function getShareholders() external view returns (address[] memory) {
        return s_shareholders.shareholders();
    }

    /**
     * @notice Get the total amount of shares owned by a user
     * @dev This is expected to be 0 if `balanceOf(user)` < `s_minimumTokenBalanceForDividends`
     * @return The total shares amount
     */
    function getSharesBalanceOf(address user) external view returns (uint256) {
        return s_shareholders.sharesOf(user);
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
     * @notice Get the total amount of staked tokens
     * @return The total staked tokens amount
     */
    function getTotalStakedAmount() external view returns (uint256) {
        return s_totalStakedAmount;
    }

    /**
     * @notice Get the minimum token balance required to start earning dividends
     * @return The minimum token balance for dividends
     */
    function getMinimumTokenBalanceForDividends() external view returns (uint256) {
        return s_minimumTokenBalanceForDividends;
    }

    /**
     * @notice Returns the total amount of dividends distributed by the contract
     *
     */
    function getTotalDividendsDistributed() external view returns (uint256) {
        return s_totalDividendsDistributed;
    }

    /**
     * @notice Get the address of the token that will be distributed as dividends
     * @return The address of the dividend token
     */
    function getDividendToken() external view returns (address) {
        return s_dividendToken;
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
        if (to == address(this)) {
            revert RayFi__CannotManuallySendRayFiTokensToTheContract();
        }

        if (s_automatedMarketMakerPairs[from] && !s_isFeeExempt[to]) {
            // Buy order
            uint8 buyFee = s_buyFee;
            if (buyFee >= 1) {
                value -= _takeFee(from, value, buyFee);
            }
        } else if (s_automatedMarketMakerPairs[to] && !s_isFeeExempt[from]) {
            // Sell order
            uint8 sellFee = s_sellFee;
            if (sellFee >= 1) {
                value -= _takeFee(from, value, sellFee);
            }
        }

        super._update(from, to, value);

        _updateShareholder(from);
        _updateShareholder(to);
    }

    /**
     * @dev Takes a fee from the transaction and updates the dividend tracker
     * @param from The address of the sender
     * @param value The amount of tokens to take the fee from
     * @param fee The fee percentage to take
     * @return feeAmount The amount of the fee
     */
    function _takeFee(address from, uint256 value, uint8 fee) private returns (uint256 feeAmount) {
        feeAmount = value * fee / 100;
        super._update(from, s_feeReceiver, feeAmount);
        _updateShareholder(s_feeReceiver);
    }

    /**
     * @dev Updates the shareholder list based on the new balance
     * @param shareholder The address of the shareholder
     */
    function _updateShareholder(address shareholder) private {
        uint256 balance = balanceOf(shareholder);
        uint256 totalBalance = balance + s_stakedBalances[shareholder];
        if (totalBalance >= s_minimumTokenBalanceForDividends && !s_isExcludedFromDividends[shareholder]) {
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
     * @dev Low-level function to unstake RayFi tokens
     * @param user The address of the user to unstake the RayFi tokens for
     * @param value The amount of RayFi tokens to unstake
     */
    function _unstake(address user, uint256 value) private {
        s_stakedBalances[user] -= value;
        s_totalStakedAmount -= value;

        emit RayFiUnstaked(user, value, s_totalStakedAmount);
    }

    /**
     * @dev Low-level function to swap dividends for RayFi tokens
     * We have to send the output of the swap to a separate wallet `s_dividendReceiver`
     * This is because V2 pools disallow setting the recipient of a swap as one of the tokens being swapped
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
                s_dividendReceiver,
                block.timestamp
            )
        );
        if (!success) {
            revert RayFi__ReinvestSwapFailed();
        }
    }

    /**
     * @dev Low-level function to process dividends for all token holders in either stateful or stateless mode
     * @param gasForDividends The amount of gas to use for processing dividends
     * @param magnifiedDividendPerShare The magnified dividend amount per share
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     * @param isStateful Whether to save the state of the distribution
     */
    function _processDividends(
        uint256 gasForDividends,
        uint256 magnifiedDividendPerShare,
        uint256 magnifiedRayFiPerShare,
        bool isStateful
    ) private {
        uint256 startingGas = gasleft();
        if (startingGas <= gasForDividends - 1) {
            revert RayFi__InsufficientGas(gasForDividends, startingGas);
        }

        uint256 shareholderCount = s_shareholders.length();
        if (shareholderCount <= 0) {
            revert RayFi__ZeroShareholders();
        }

        if (isStateful) {
            _runDividendLoopStateFul(
                gasForDividends, startingGas, shareholderCount, magnifiedDividendPerShare, magnifiedRayFiPerShare
            );
        } else {
            _runDividendLoopStateLess(
                gasForDividends, startingGas, shareholderCount, magnifiedDividendPerShare, magnifiedRayFiPerShare
            );
        }
    }

    /**
     * @dev Low-level function to run the dividend distribution loop in a stateless manner
     * @param gasForDividends The amount of gas to use for processing dividends
     * @param startingGas The amount of gas at the start of the function
     * @param shareholderCount The total number of shareholders
     * @param magnifiedDividendPerShare The magnified dividend amount per share
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     */
    function _runDividendLoopStateLess(
        uint256 gasForDividends,
        uint256 startingGas,
        uint256 shareholderCount,
        uint256 magnifiedDividendPerShare,
        uint256 magnifiedRayFiPerShare
    ) private {
        uint256 lastProcessedIndex;
        uint256 gasUsed;
        while (gasUsed <= gasForDividends - 1) {
            _processDividendOfUserStateLess(
                s_shareholders.shareholderAt(lastProcessedIndex), magnifiedDividendPerShare, magnifiedRayFiPerShare
            );

            lastProcessedIndex++;
            if (lastProcessedIndex >= shareholderCount) {
                return;
            }

            gasUsed += startingGas - gasleft();
        }
        revert RayFi__StateLessDistributionCouldNotComplete(shareholderCount, lastProcessedIndex);
    }

    /**
     * @dev Low-level function to run the dividend distribution loop in a stateful manner
     * @param gasForDividends The amount of gas to use for processing dividends
     * @param startingGas The amount of gas at the start of the function
     * @param shareholderCount The total number of shareholders
     * @param magnifiedDividendPerShare The magnified dividend amount per share
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     */
    function _runDividendLoopStateFul(
        uint256 gasForDividends,
        uint256 startingGas,
        uint256 shareholderCount,
        uint256 magnifiedDividendPerShare,
        uint256 magnifiedRayFiPerShare
    ) private {
        uint256 lastProcessedIndex = s_lastProcessedIndex;
        uint256 gasUsed;
        while (gasUsed <= gasForDividends - 1) {
            _processDividendOfUserStateFul(
                s_shareholders.shareholderAt(lastProcessedIndex), magnifiedDividendPerShare, magnifiedRayFiPerShare
            );

            lastProcessedIndex++;
            if (lastProcessedIndex >= shareholderCount) {
                delete lastProcessedIndex;
                delete s_magnifiedDividendPerShare;
                delete s_magnifiedRayFiPerShare;

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
    function _processDividendOfUserStateLess(
        address user,
        uint256 magnifiedDividendPerShare,
        uint256 magnifiedRayFiPerShare
    ) private {
        uint256 earnedDividend = _getEarnedDividend(user, magnifiedDividendPerShare);
        uint256 earnedRayFi = _getEarnedRayFi(user, magnifiedRayFiPerShare);

        if (earnedDividend >= 1) {
            ERC20(s_dividendToken).transfer(user, earnedDividend);

            emit DividendsWithdrawn(user, earnedDividend);
        }
        if (earnedRayFi >= 1) {
            super._update(s_dividendReceiver, address(this), earnedRayFi);
            _stake(user, earnedRayFi);

            emit DividendsReinvested(user, earnedRayFi);
        }
    }

    /**
     * @notice Processes dividends for a specific token holder, saving the state of the distribution to storage
     * @param user The address of the token holder
     * @param magnifiedDividendPerShare The magnified dividend amount per share
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     */
    function _processDividendOfUserStateFul(
        address user,
        uint256 magnifiedDividendPerShare,
        uint256 magnifiedRayFiPerShare
    ) private {
        uint256 lastShareholderSnapshotIndex = s_shareholdersSnapshots.length - 1;
        uint256 earnedDividend =
            _getLastEarnedDividendAtSnapshot(user, magnifiedDividendPerShare, lastShareholderSnapshotIndex);
        uint256 earnedRayFi = _getEarnedRayFiAtSnapshot(user, magnifiedRayFiPerShare, lastShareholderSnapshotIndex);

        if (earnedDividend >= 1) {
            s_shareholdersSnapshots[lastShareholderSnapshotIndex].addWithdrawnDividends(user, earnedDividend);

            (bool success) = ERC20(s_dividendToken).transfer(user, earnedDividend);

            if (!success) {
                s_shareholdersSnapshots[lastShareholderSnapshotIndex].addWithdrawnDividends(user, 0);
            } else {
                emit DividendsWithdrawn(user, earnedDividend);
            }
        }
        if (earnedRayFi >= 1) {
            s_shareholdersSnapshots[lastShareholderSnapshotIndex].addReinvestedRayFi(user, earnedRayFi);

            super._update(s_dividendReceiver, address(this), earnedRayFi);
            _stake(user, earnedRayFi);

            emit DividendsReinvested(user, earnedRayFi);
        }
    }

    /**
     * @dev Low-level function to snapshot the current shareholders
     * This is used to resume the dividend distribution from the last cycle
     */
    function _snapshotShareholders() private {
        RayFiLibrary.ShareholderSet storage s_lastShareholderSnapshot = s_shareholdersSnapshots.push();
        address[] memory shareholders = s_shareholders.shareholders();
        for (uint256 i = 0; i <= shareholders.length - 1; i++) {
            address shareholder = shareholders[i];
            s_lastShareholderSnapshot.add(shareholder, s_shareholders.sharesOf(shareholder));
            s_lastShareholderSnapshot.addStakedShares(shareholder, s_stakedBalances[shareholder]);
        }
    }

    //////////////////////////////////////
    // Private View & Pure Functions    //
    //////////////////////////////////////

    /**
     * @notice View the amount of dividend that an address has earned in the current cycle
     * @param user The address of a token holder
     * @param magnifiedDividendPerShare The magnified dividend amount per share
     * @return The amount of dividend that `user` has earned
     */
    function _getEarnedDividend(address user, uint256 magnifiedDividendPerShare) private view returns (uint256) {
        return _calculateDividend(magnifiedDividendPerShare, balanceOf(user));
    }

    /**
     * @dev View the amount of dividend that an address has earned during a specific cycle
     * Used to resume the dividend distribution from the given cycle
     * @param user The address of a token holder
     * @param magnifiedDividendPerShare The magnified dividend amount per share
     * @param snapshotIndex The index of the snapshot to use
     * @return The amount of dividend that `user` has earned in the given cycle
     */
    function _getLastEarnedDividendAtSnapshot(address user, uint256 magnifiedDividendPerShare, uint256 snapshotIndex)
        private
        view
        returns (uint256)
    {
        return _calculateDividend(magnifiedDividendPerShare, s_shareholdersSnapshots[snapshotIndex].sharesOf(user))
            - s_shareholdersSnapshots[snapshotIndex].withdrawnDividendsOf(user);
    }

    /**
     * @notice View the amount of RayFi that an address has earned in the current cycle
     * @param user The address of a token holder
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     * @return The amount of RayFi that `user` has earned
     */
    function _getEarnedRayFi(address user, uint256 magnifiedRayFiPerShare) private view returns (uint256) {
        return _calculateDividend(magnifiedRayFiPerShare, s_stakedBalances[user]);
    }

    /**
     * @dev View the amount of RayFi that an address has earned during a specific cycle
     * Used to resume the dividend distribution from the given cycle
     * @param user The address of a token holder
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     * @param snapshotIndex The index of the snapshot to use
     * @return The amount of RayFi that `user` has earned in the given cycle
     */
    function _getEarnedRayFiAtSnapshot(address user, uint256 magnifiedRayFiPerShare, uint256 snapshotIndex)
        private
        view
        returns (uint256)
    {
        return _calculateDividend(magnifiedRayFiPerShare, s_shareholdersSnapshots[snapshotIndex].stakedSharesOf(user))
            - s_shareholdersSnapshots[snapshotIndex].reinvestedRayFiOf(user);
    }

    /**
     * @dev Low-level function to de-magnify the dividend amount per share for a given balance
     * @param magnifiedDividendPerShare The magnified dividend amount per share
     * @param balance The balance to use as reference
     * @return The de-magnified dividend amount
     */
    function _calculateDividend(uint256 magnifiedDividendPerShare, uint256 balance) private pure returns (uint256) {
        return magnifiedDividendPerShare * balance / MAGNITUDE;
    }

    /**
     * @dev Low-level function to calculate the magnified amount of dividend per share
     * @param totalDividends The total amount of dividends
     * @param totalShares The total amount of shares
     * @return The magnified amount of dividend per share
     */
    function _calculateDividendPerShare(uint256 totalDividends, uint256 totalShares) private pure returns (uint256) {
        return totalDividends * MAGNITUDE / totalShares;
    }
}
