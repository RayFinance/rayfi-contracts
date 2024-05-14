// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

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

    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /////////////////////
    // State Variables //
    /////////////////////

    uint256 private constant MAX_SUPPLY = 10_000_000;
    uint256 private constant MAX_FEES = 10;
    uint256 private constant MAGNITUDE = 2 ** 128;

    uint256 private s_totalStakedAmount;
    uint256 private s_totalSharesAmount;
    uint256 private s_minimumTokenBalanceForRewards;
    uint256 private s_magnifiedRayFiPerShare;
    uint256 private s_magnifiedRewardPerShare;
    uint256 private s_lastProcessedIndex;

    address private s_rewardToken;
    address private s_router;
    address private s_feeReceiver;
    address private s_rewardReceiver;

    uint8 private s_buyFee;
    uint8 private s_sellFee;

    mapping(address user => bool isExemptFromFees) private s_isFeeExempt;
    mapping(address user => bool isExcludedFromRewards) private s_isExcludedFromRewards;
    mapping(address pair => bool isAMMPair) private s_automatedMarketMakerPairs;
    mapping(address user => uint256 amountStaked) private s_stakedBalances;
    mapping(address user => uint256 withdrawnRewards) private s_withdrawnRewards;
    mapping(address user => uint256 reinvestedRayFi) private s_reinvestedRayFi;

    EnumerableMap.AddressToUintMap private s_shareholders;

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
     * @notice Emitted when the reward receiver is updated
     * @param newRewardReceiver The new reward receiver
     * @param oldRewardReceiver The old reward receiver
     */
    event RewardReceiverUpdated(address indexed newRewardReceiver, address indexed oldRewardReceiver);

    /**
     * @notice Emitted when the reward token is updated
     * @param newRewardToken The new reward token
     * @param oldRewardToken The old reward token
     */
    event RewardTokenUpdated(address indexed newRewardToken, address indexed oldRewardToken);

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
     * @notice Emitted when the minimum token balance for rewards is updated
     * @param newMinimum The new minimum token balance for rewards
     * @param oldMinimum The previous minimum token balance for rewards
     */
    event MinimumTokenBalanceForRewardsUpdated(uint256 indexed newMinimum, uint256 indexed oldMinimum);

    /**
     * @notice Emitted when a user is marked as excluded from rewards
     * @param user The address of the user
     * @param isExcluded Whether the user is excluded from rewards
     */
    event IsUserExcludedFromRewardsUpdated(address indexed user, bool indexed isExcluded);

    /**
     * @notice Emitted when rewards are distributed
     * @param totalRewardsWithdrawn The amount of rewards that were airdropped to users
     * @param totalRayFiStaked The amount of RayFi that was staked after reinvesting rewards
     */
    event RewardsDistributed(uint256 indexed totalRewardsWithdrawn, uint256 indexed totalRayFiStaked);

    /**
     * @notice Emitted when rewards are withdrawn
     * @param user The user that withdrew the rewards
     * @param amount The amount of rewards that were withdrawn
     */
    event RewardsWithdrawn(address indexed user, uint256 indexed amount);

    /**
     * @notice Emitted when rewards are reinvested
     * @param user The user that reinvested the rewards
     * @param amount The amount of RayFi that was compounded
     */
    event RewardsReinvested(address indexed user, uint256 indexed amount);

    //////////////////
    // Errors       //
    //////////////////

    /**
     * @notice Triggered when trying to send RayFi tokens to this contract
     * Users should call the `stake` function to stake their RayFi tokens
     * @dev Sending RayFi tokens to the contract is not allowed to prevent accidental staking
     * This also simplifies reward tracking and distribution logic
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
     * @dev Triggered when trying to process rewards, but not enough gas was sent with the transaction
     * @param gasRequested The amount of gas requested
     * @param gasProvided The amount of gas provided
     */
    error RayFi__InsufficientGas(uint256 gasRequested, uint256 gasProvided);

    /**
     * @dev Triggered when trying to process rewards, but there are no shareholders
     */
    error RayFi__ZeroShareholders();

    /**
     * @dev Triggered when trying to distribute rewards, but there are no rewards to distribute
     */
    error RayFi__NothingToDistribute();

    /**
     * @dev Triggered when trying to reinvest rewards, but the swap failed
     */
    error RayFi__ReinvestSwapFailed();

    ////////////////////
    // Constructor    //
    ////////////////////

    /**
     * @param rewardToken The address of the token that will be used to distribute rewards
     * @param router The address of the router that will be used to reinvest rewards
     * @param feeReceiver The address of the contract that will track rewards
     * @param rewardReceiver The address of the wallet that will distribute swapped rewards
     */
    constructor(address rewardToken, address router, address feeReceiver, address rewardReceiver)
        ERC20("RayFi", "RAYFI")
        Ownable(msg.sender)
    {
        if (
            rewardToken == address(0) || router == address(0) || feeReceiver == address(0)
                || rewardReceiver == address(0)
        ) {
            revert RayFi__CannotSetToZeroAddress();
        }

        s_rewardToken = rewardToken;
        s_router = router;
        s_feeReceiver = feeReceiver;
        s_rewardReceiver = rewardReceiver;
        s_isFeeExempt[rewardReceiver] = true;
        s_isExcludedFromRewards[rewardReceiver] = true;
        s_isExcludedFromRewards[address(this)] = true;
        s_isExcludedFromRewards[address(0)] = true;

        _mint(msg.sender, MAX_SUPPLY * (10 ** decimals()));
    }

    ///////////////////////////
    // External Functions    //
    ///////////////////////////

    /**
     * @notice This function allows users to stake their RayFi tokens to have their rewards reinvested in RayFi
     * @param value The amount of tokens to stake
     */
    function stake(uint256 value) external {
        uint256 minimumTokenBalanceForRewards = s_minimumTokenBalanceForRewards;
        value += s_stakedBalances[msg.sender];
        if (minimumTokenBalanceForRewards >= value + 1) {
            revert RayFi__InsufficientTokensToStake(value, minimumTokenBalanceForRewards);
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
        if (value >= stakedBalance + 1) {
            revert RayFi__InsufficientStakedBalance(stakedBalance, value);
        }

        _unstake(msg.sender, value);
        super._update(address(this), msg.sender, value);
        _updateShareholder(msg.sender);
    }

    /**
     * @notice High-level function to start the reward distribution process in either stateful or stateless mode
     * The stateless mode is always the preferred one, as it is drastically more gas-efficient
     * The stateful mode is a backup to use only in case the stateless mode is unable to complete the distribution
     * Rewards are either sent to users as stablecoins or reinvested into RayFi for users who have staked their tokens
     * @dev In each distribution, there is a small amount of stablecoins not distributed,
     * the magnified amount of which is `(amount * MAGNITUDE) % totalSupply()`
     * With a well-chosen `MAGNITUDE`, this amount (de-magnified) can be less than 1 wei
     * We can actually keep track of the undistributed stablecoins for the next distribution,
     * but keeping track of such data on-chain costs much more than the saved stablecoins, so we do not do that
     * @param gasForRewards The amount of gas to use for processing rewards in a stateful
     * This is a safety mechanism to prevent the contract from running out of gas at an inconvenient time
     * `gasForRewards` should be set to a value that is less than the gas limit of the transaction
     * This parameter is ignored in stateless mode
     * @param isStateful Whether to save the state of the distribution to resume it later
     */
    function distributeRewards(uint256 gasForRewards, bool isStateful) external onlyOwner {
        uint256 totalUnclaimedRewards = ERC20(s_rewardToken).balanceOf(address(this));
        if (totalUnclaimedRewards <= 0) {
            revert RayFi__NothingToDistribute();
        }

        uint256 totalSharesAmount = s_totalSharesAmount;
        if (totalSharesAmount <= 0) {
            revert RayFi__ZeroShareholders();
        }

        uint256 magnifiedRewardPerShare;
        uint256 magnifiedRayFiPerShare;

        uint256 totalStakedAmount = s_totalStakedAmount;
        if (totalStakedAmount >= 1) {
            uint256 rewardsToReinvest = totalUnclaimedRewards * totalStakedAmount / totalSharesAmount;
            address rewardReceiver = s_rewardReceiver;
            _swapRewardsForRayFi(rewardReceiver, rewardsToReinvest);

            uint256 rayFiToDistribute = balanceOf(rewardReceiver);
            uint256 rewardsToDistribute = totalUnclaimedRewards - rewardsToReinvest;

            uint256 totalNonStakedAmount = totalSharesAmount - totalStakedAmount;
            magnifiedRewardPerShare =
                totalNonStakedAmount >= 1 ? _calculateRewardPerShare(rewardsToDistribute, totalNonStakedAmount) : 0;
            magnifiedRayFiPerShare = _calculateRewardPerShare(rayFiToDistribute, totalStakedAmount);
        } else {
            magnifiedRewardPerShare = _calculateRewardPerShare(totalUnclaimedRewards, totalSharesAmount);
        }

        if (isStateful) {
            uint256 lastMagnifiedRewardPerShare = s_magnifiedRewardPerShare;
            uint256 lastMagnifiedRayFiPerShare = s_magnifiedRayFiPerShare;
            if (lastMagnifiedRewardPerShare >= 1 || lastMagnifiedRayFiPerShare >= 1) {
                // Distribute the undistributed rewards from the last cycle
                magnifiedRewardPerShare = lastMagnifiedRewardPerShare;
                magnifiedRayFiPerShare = lastMagnifiedRayFiPerShare;
            } else {
                s_magnifiedRewardPerShare = magnifiedRayFiPerShare;
                s_magnifiedRayFiPerShare = magnifiedRewardPerShare;
            }
        }

        _processRewards(gasForRewards, magnifiedRewardPerShare, magnifiedRayFiPerShare, isStateful);
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
     * @notice Sets the minimum token balance for rewards
     * @param newMinimum The new minimum token balance for rewards
     */
    function setMinimumTokenBalanceForRewards(uint256 newMinimum) external onlyOwner {
        uint256 oldMinimum = s_minimumTokenBalanceForRewards;
        s_minimumTokenBalanceForRewards = newMinimum;
        emit MinimumTokenBalanceForRewardsUpdated(newMinimum, oldMinimum);
    }

    /**
     * @notice Sets whether an address is excluded from rewards
     * @param user The address to update
     * @param isExcluded Whether the address is excluded from rewards
     */
    function setIsExcludedFromRewards(address user, bool isExcluded) external onlyOwner {
        s_isExcludedFromRewards[user] = isExcluded;
        if (s_shareholders.contains(user)) {
            s_shareholders.remove(user);
            s_totalSharesAmount -= balanceOf(user);
        }
        emit IsUserExcludedFromRewardsUpdated(user, isExcluded);
    }

    /**
     * @notice Sets whether an address is exempt from fees
     * @param user The address to update
     * @param isExempt Whether the address is exempt from fees
     */
    function setIsFeeExempt(address user, bool isExempt) external onlyOwner {
        s_isFeeExempt[user] = isExempt;
        emit IsUserExemptFromFeesUpdated(user, isExempt);
    }

    /**
     * @notice Sets the address of the token that will be distributed as rewards
     * @param newRewardToken The address of the new reward token
     */
    function setRewardToken(address newRewardToken) external onlyOwner {
        if (newRewardToken == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        }
        address oldRewardToken = s_rewardToken;
        s_rewardToken = newRewardToken;
        emit RewardTokenUpdated(newRewardToken, oldRewardToken);
    }

    /**
     * @notice Sets the address of the router that will be used to reinvest rewards
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
     * @notice Sets the address of the wallet that will receive swapped rewards
     * @param newRewardReceiver The address of the new reward receiver
     */
    function setRewardReceiver(address newRewardReceiver) external onlyOwner {
        if (newRewardReceiver == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        }
        address oldRewardReceiver = s_rewardReceiver;
        s_rewardReceiver = newRewardReceiver;
        emit RewardReceiverUpdated(newRewardReceiver, oldRewardReceiver);
    }

    ////////////////////////////////
    // External View Functions    //
    ////////////////////////////////

    /**
     * @notice Get the current shareholders of the RayFi protocol
     * @return The list of shareholders
     */
    function getShareholders() external view returns (address[] memory) {
        return s_shareholders.keys();
    }

    /**
     * @notice Get the total amount of shares owned by a user
     * @dev This is expected to be 0 if `balanceOf(user)` < `s_minimumTokenBalanceForRewards`
     * @return The total shares amount
     */
    function getSharesBalanceOf(address user) external view returns (uint256) {
        return s_shareholders.get(user);
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
     * @notice Get the minimum token balance required to start earning rewards
     * @return The minimum token balance for rewards
     */
    function getMinimumTokenBalanceForRewards() external view returns (uint256) {
        return s_minimumTokenBalanceForRewards;
    }

    /**
     * @notice Get the address of the token that will be distributed as rewards
     * @return The address of the reward token
     */
    function getRewardToken() external view returns (address) {
        return s_rewardToken;
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
     * @dev Overrides the internal `_update` function to include fee logic and update the reward tracker
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
        } else if (!s_isFeeExempt[from] && !s_isFeeExempt[to]) {
            // Transfer
            uint8 transferFee = s_buyFee + s_sellFee;
            if (transferFee >= 1) {
                value -= _takeFee(from, value, transferFee);
            }
        }

        super._update(from, to, value);

        _updateShareholder(from);
        _updateShareholder(to);
    }

    /**
     * @dev Takes a fee from the transaction and updates the reward tracker
     * @param from The address of the sender
     * @param value The amount of tokens to take the fee from
     * @param fee The fee percentage to take
     * @return feeAmount The amount of the fee
     */
    function _takeFee(address from, uint256 value, uint8 fee) private returns (uint256 feeAmount) {
        feeAmount = value * fee / 100;
        address feeReceiver = s_feeReceiver;
        super._update(from, feeReceiver, feeAmount);
        _updateShareholder(feeReceiver);
    }

    /**
     * @dev Updates the shareholder list based on the new balance
     * @param shareholder The address of the shareholder
     */
    function _updateShareholder(address shareholder) private {
        uint256 balance = balanceOf(shareholder);
        uint256 totalBalance = balance + s_stakedBalances[shareholder];
        if (totalBalance >= s_minimumTokenBalanceForRewards && !s_isExcludedFromRewards[shareholder]) {
            (bool success, uint256 oldBalance) = s_shareholders.tryGet(shareholder);
            if (!success) {
                s_totalSharesAmount += totalBalance;
            } else {
                s_totalSharesAmount = s_totalSharesAmount + totalBalance - oldBalance;
            }
            s_shareholders.set(shareholder, balance);
        } else {
            s_shareholders.remove(shareholder);
            s_totalSharesAmount -= totalBalance;
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
     * @dev Low-level function to swap rewards for RayFi tokens
     * We have to send the output of the swap to a separate wallet `rewardReceiver`
     * This is because V2 pools disallow setting the recipient of a swap as one of the tokens being swapped
     * @param rewardReceiver The address of the wallet that will receive the swapped rewards
     * @param amount The amount of rewards to swap
     */
    function _swapRewardsForRayFi(address rewardReceiver, uint256 amount) private {
        address rewardToken = s_rewardToken;
        ERC20(rewardToken).approve(address(s_router), amount);

        address[] memory path = new address[](2);
        path[0] = rewardToken;
        path[1] = address(this);
        (bool success,) = s_router.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                amount,
                0,
                path,
                rewardReceiver,
                block.timestamp
            )
        );
        if (!success) {
            revert RayFi__ReinvestSwapFailed();
        }
    }

    /**
     * @dev Low-level function to process rewards for all token holders in either stateful or stateless mode
     * @param gasForRewards The amount of gas to use for processing rewards
     * @param magnifiedRewardPerShare The magnified reward amount per share
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     * @param isStateful Whether to save the state of the distribution
     */
    function _processRewards(
        uint256 gasForRewards,
        uint256 magnifiedRewardPerShare,
        uint256 magnifiedRayFiPerShare,
        bool isStateful
    ) private {
        uint256 shareholderCount = s_shareholders.length();
        if (isStateful) {
            _runRewardLoopStateFul(gasForRewards, shareholderCount, magnifiedRewardPerShare, magnifiedRayFiPerShare);
        } else {
            uint256 withdrawnRewards;
            uint256 stakedRayFi;
            for (uint256 i; i < shareholderCount; ++i) {
                (address user,) = s_shareholders.at(i);
                (uint256 withdrawnRewardOfUser, uint256 stakedRayFiOfUser) =
                    _processRewardOfUserStateless(user, magnifiedRewardPerShare, magnifiedRayFiPerShare);
                withdrawnRewards += withdrawnRewardOfUser;
                stakedRayFi += stakedRayFiOfUser;
            }

            if (stakedRayFi >= 1) {
                super._update(s_rewardReceiver, address(this), stakedRayFi);
                s_totalStakedAmount += stakedRayFi;
            }

            emit RewardsDistributed(withdrawnRewards, stakedRayFi);
        }
    }

    /**
     * @dev Low-level function to run the reward distribution loop in a stateful manner
     * @param gasForRewards The amount of gas to use for processing rewards
     * @param shareholderCount The total number of shareholders
     * @param magnifiedRewardPerShare The magnified reward amount per share
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     */
    function _runRewardLoopStateFul(
        uint256 gasForRewards,
        uint256 shareholderCount,
        uint256 magnifiedRewardPerShare,
        uint256 magnifiedRayFiPerShare
    ) private {
        uint256 startingGas = gasleft();
        if (gasForRewards >= startingGas) {
            revert RayFi__InsufficientGas(gasForRewards, startingGas);
        }

        uint256 lastProcessedIndex = s_lastProcessedIndex;
        uint256 gasUsed;
        while (gasUsed < gasForRewards) {
            (address user,) = s_shareholders.at(lastProcessedIndex);
            _processRewardOfUserStateFul(user, magnifiedRewardPerShare, magnifiedRayFiPerShare);

            ++lastProcessedIndex;
            if (lastProcessedIndex >= shareholderCount) {
                delete lastProcessedIndex;
                delete s_magnifiedRewardPerShare;
                delete s_magnifiedRayFiPerShare;

                break;
            }

            gasUsed += startingGas - gasleft();
        }
        s_lastProcessedIndex = lastProcessedIndex;
    }

    /**
     * @notice Processes rewards for a specific token holder
     * @param user The address of the token holder
     * @param magnifiedRewardPerShare The magnified reward amount per share
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     */
    function _processRewardOfUserStateless(
        address user,
        uint256 magnifiedRewardPerShare,
        uint256 magnifiedRayFiPerShare
    ) private returns (uint256 withdrawableReward, uint256 reinvestableRayFi) {
        withdrawableReward = _calculateReward(magnifiedRewardPerShare, balanceOf(user));
        reinvestableRayFi = _calculateReward(magnifiedRayFiPerShare, s_stakedBalances[user]);

        if (withdrawableReward >= 1) {
            ERC20(s_rewardToken).transfer(user, withdrawableReward);
        }
        if (reinvestableRayFi >= 1) {
            unchecked {
                s_stakedBalances[user] += reinvestableRayFi;
            }
        }
    }

    /**
     * @notice Processes rewards for a specific token holder, saving the state of the distribution to storage
     * @param user The address of the token holder
     * @param magnifiedRewardPerShare The magnified reward amount per share
     * @param magnifiedRayFiPerShare The magnified RayFi amount per share
     */
    function _processRewardOfUserStateFul(address user, uint256 magnifiedRewardPerShare, uint256 magnifiedRayFiPerShare)
        private
    {
        uint256 withdrawableReward =
            _calculateReward(magnifiedRewardPerShare, balanceOf(user)) - s_withdrawnRewards[user];
        uint256 reinvestableRayFi =
            _calculateReward(magnifiedRayFiPerShare, s_stakedBalances[user]) - s_reinvestedRayFi[user];

        if (withdrawableReward >= 1) {
            s_withdrawnRewards[user] += withdrawableReward;

            (bool success) = ERC20(s_rewardToken).transfer(user, withdrawableReward);

            if (!success) {
                s_withdrawnRewards[user] -= withdrawableReward;
            } else {
                emit RewardsWithdrawn(user, withdrawableReward);
            }
        }
        if (reinvestableRayFi >= 1) {
            s_reinvestedRayFi[user] += reinvestableRayFi;

            super._update(s_rewardReceiver, address(this), reinvestableRayFi);
            _stake(user, reinvestableRayFi);

            emit RewardsReinvested(user, reinvestableRayFi);
        }
    }

    //////////////////////////////////////
    // Private View & Pure Functions    //
    //////////////////////////////////////

    /**
     * @dev Low-level function to de-magnify the reward amount per share for a given balance
     * @param magnifiedRewardPerShare The magnified reward amount per share
     * @param balance The balance to use as reference
     * @return The de-magnified reward amount
     */
    function _calculateReward(uint256 magnifiedRewardPerShare, uint256 balance) private pure returns (uint256) {
        return magnifiedRewardPerShare * balance / MAGNITUDE;
    }

    /**
     * @dev Low-level function to calculate the magnified amount of reward per share
     * @param totalRewards The total amount of rewards
     * @param totalShares The total amount of shares
     * @return The magnified amount of reward per share
     */
    function _calculateRewardPerShare(uint256 totalRewards, uint256 totalShares) private pure returns (uint256) {
        return totalRewards * MAGNITUDE / totalShares;
    }
}
