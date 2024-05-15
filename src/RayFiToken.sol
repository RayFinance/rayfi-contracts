// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

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

    struct Vault {
        address[] users;
        uint256 vaultId;
        uint256 totalVaultShares;
        uint256 magnifiedRewardPerShare;
        uint256 lastProcessedIndex;
        mapping(address user => uint256 position) positions;
        mapping(address user => uint256 amount) vaultBalances;
        mapping(address user => uint256 withdrawnRewards) withdrawnRewards;
    }

    /////////////////////
    // State Variables //
    /////////////////////

    uint256 private constant MAX_SUPPLY = 10_000_000;
    uint256 private constant MAX_FEES = 10;
    uint256 private constant MAGNITUDE = 2 ** 128;

    uint256 private s_totalStakedShares;
    uint256 private s_totalRewardShares;
    uint256 private s_minimumTokenBalanceForRewards;
    uint256 private s_magnifiedRayFiPerShare;
    uint256 private s_magnifiedRewardPerShare;
    uint256 private s_lastProcessedIndex;

    IUniswapV2Router02 private s_router;

    address private s_rewardToken;
    address private s_feeReceiver;
    address private s_swapReceiver;

    uint8 private s_buyFee;
    uint8 private s_sellFee;

    mapping(address user => bool isExemptFromFees) private s_isFeeExempt;
    mapping(address user => bool isExcludedFromRewards) private s_isExcludedFromRewards;
    mapping(address pair => bool isAMMPair) private s_automatedMarketMakerPairs;
    mapping(address user => uint256 amountStaked) private s_stakedBalances;
    mapping(address user => uint256 withdrawnRewards) private s_withdrawnRewards;
    mapping(address user => uint256 reinvestedRayFi) private s_reinvestedRayFi;
    mapping(address token => Vault vault) private s_vaults;

    address[] private s_vaultTokens;

    EnumerableMap.AddressToUintMap private s_shareholders;

    ////////////////
    /// Events    //
    ////////////////

    /**
     * @notice Emitted when RayFi is staked
     * @param staker The address of the user that staked the RayFi
     * @param stakedAmount The amount of RayFi that was staked
     * @param totalStakedShares The total amount of RayFi staked in this contract
     */
    event RayFiStaked(address indexed staker, uint256 indexed stakedAmount, uint256 indexed totalStakedShares);

    /**
     * @notice Emitted when RayFi is unstaked
     * @param unstaker The address of the user that unstaked the RayFi
     * @param unstakedAmount The amount of RayFi that was unstaked
     * @param totalStakedShares The total amount of RayFi staked in this contract
     */
    event RayFiUnstaked(address indexed unstaker, uint256 indexed unstakedAmount, uint256 indexed totalStakedShares);

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
     * @notice Emitted when the swap receiver is updated
     * @param newSwapReceiver The new swap receiver
     * @param oldSwapReceiver The old swap receiver
     */
    event SwapReceiverUpdated(address indexed newSwapReceiver, address indexed oldSwapReceiver);

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
     * @dev Triggered when trying to add a vault that already exists
     * @param vaultToken The address of the vault that already exists
     */
    error RayFi__VaultAlreadyExists(address vaultToken);

    /**
     * @dev Triggered when trying to interact with a vault that does not exist
     * @param vaultToken The address of the vault that does not exist
     */
    error RayFi__VaultDoesNotExist(address vaultToken);

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
     * @dev Triggered when a swap fails
     */
    error RayFi__SwapFailed();

    ////////////////////
    // Constructor    //
    ////////////////////

    /**
     * @param rewardToken The address of the token that will be used to distribute rewards
     * @param router The address of the router that will be used to reinvest rewards
     * @param feeReceiver The address of the contract that will track rewards
     * @param swapReceiver The address of the wallet that will distribute swapped rewards
     */
    constructor(address rewardToken, address router, address feeReceiver, address swapReceiver)
        ERC20("RayFi", "RAYFI")
        Ownable(msg.sender)
    {
        if (
            rewardToken == address(0) || router == address(0) || feeReceiver == address(0) || swapReceiver == address(0)
        ) {
            revert RayFi__CannotSetToZeroAddress();
        }

        s_rewardToken = rewardToken;
        s_router = IUniswapV2Router02(router);
        s_feeReceiver = feeReceiver;
        s_swapReceiver = swapReceiver;

        s_isFeeExempt[swapReceiver] = true;

        s_isExcludedFromRewards[swapReceiver] = true;
        s_isExcludedFromRewards[address(this)] = true;
        s_isExcludedFromRewards[address(0)] = true;

        s_vaultTokens.push(address(this));
        s_vaults[address(this)].vaultId = s_vaultTokens.length;

        _mint(msg.sender, MAX_SUPPLY * (10 ** decimals()));
    }

    ///////////////////////////
    // External Functions    //
    ///////////////////////////

    /**
     * @notice This function allows users to stake their RayFi tokens to have their rewards reinvested in RayFi
     * @param value The amount of tokens to stake
     */
    function stake(address vault, uint256 value) external {
        uint256 minimumTokenBalanceForRewards = s_minimumTokenBalanceForRewards;
        if (value < minimumTokenBalanceForRewards) {
            revert RayFi__InsufficientTokensToStake(value, minimumTokenBalanceForRewards);
        } else if (s_vaults[vault].vaultId <= 0) {
            revert RayFi__VaultDoesNotExist(vault);
        }

        super._update(msg.sender, address(this), value);
        _stake(vault, msg.sender, value);
        _updateShareholder(msg.sender);
    }

    /**
     * @notice This function allows users to unstake their RayFi tokens
     * @dev We do not check if the vault exists so that users may withdraw from a vault that has been removed
     * @param value The amount of tokens to unstake
     */
    function unstake(address vault, uint256 value) external {
        uint256 stakedBalanceBefore = s_vaults[vault].vaultBalances[msg.sender];
        uint256 stakedBalanceAfter = stakedBalanceBefore - value;
        uint256 minimumTokenBalanceForRewards = s_minimumTokenBalanceForRewards;
        if (stakedBalanceBefore < value) {
            revert RayFi__InsufficientStakedBalance(stakedBalanceBefore, value);
        } else if (stakedBalanceAfter != 0 && stakedBalanceAfter < minimumTokenBalanceForRewards) {
            revert RayFi__InsufficientTokensToStake(stakedBalanceAfter, minimumTokenBalanceForRewards);
        }

        _unstake(vault, msg.sender, value);
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
     * @param vaultTokens The list of vaults to distribute rewards to, can be left empty to distribute to all vaults
     */
    function distributeRewards(uint32 gasForRewards, bool isStateful, uint8 slippage, address[] memory vaultTokens)
        external
        onlyOwner
    {
        uint256 totalUnclaimedRewards = ERC20(s_rewardToken).balanceOf(address(this));
        if (totalUnclaimedRewards <= 0) {
            revert RayFi__NothingToDistribute();
        }

        uint256 totalRewardShares = s_totalRewardShares;
        if (totalRewardShares <= 0) {
            revert RayFi__ZeroShareholders();
        }

        uint256 totalStakedShares = s_totalStakedShares;
        address rewardToken = s_rewardToken;
        if (totalStakedShares >= 1) {
            if (vaultTokens.length <= 0) {
                vaultTokens = s_vaultTokens;
            }

            uint256 totalRewardsToReinvest =
                totalUnclaimedRewards * totalStakedShares / (totalRewardShares + totalStakedShares);

            _runVaultLoop(
                vaultTokens, rewardToken, totalRewardsToReinvest, totalStakedShares, slippage, gasForRewards, isStateful
            );

            uint256 totalNonStakedAmount = totalRewardShares - totalStakedShares;
            if (totalNonStakedAmount >= 1) {
                totalUnclaimedRewards = ERC20(rewardToken).balanceOf(address(this));
                uint256 magnifiedRewardPerShare = _calculateRewardPerShare(totalUnclaimedRewards, totalNonStakedAmount);
                _processRewards(gasForRewards, magnifiedRewardPerShare, rewardToken, isStateful);
            }
        } else {
            uint256 magnifiedRewardPerShare = _calculateRewardPerShare(totalUnclaimedRewards, totalRewardShares);
            _processRewards(gasForRewards, magnifiedRewardPerShare, rewardToken, isStateful);
        }

        // if (isStateful) {
        //     uint256 lastMagnifiedRewardPerShare = s_magnifiedRewardPerShare;
        //     uint256 lastMagnifiedRayFiPerShare = s_magnifiedRayFiPerShare;
        //     if (lastMagnifiedRewardPerShare >= 1 || lastMagnifiedRayFiPerShare >= 1) {
        //         // Distribute the undistributed rewards from the last cycle
        //         magnifiedRewardPerShare = lastMagnifiedRewardPerShare;
        //         magnifiedRayFiPerShare = lastMagnifiedRayFiPerShare;
        //     } else {
        //         s_magnifiedRewardPerShare = magnifiedRayFiPerShare;
        //         s_magnifiedRayFiPerShare = magnifiedRewardPerShare;
        //     }
        // }
    }

    /**
     * @notice This function allows the owner to add a new vault to the RayFi protocol
     * @param vaultToken The key of the new vault, which should be the address of the associated ERC20 reward token
     */
    function addVault(address vaultToken) external onlyOwner {
        if (s_vaults[vaultToken].vaultId != 0) {
            revert RayFi__VaultAlreadyExists(vaultToken);
        } else if (vaultToken == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        } else {
            s_vaultTokens.push(vaultToken);
            s_vaults[vaultToken].vaultId = s_vaultTokens.length;
        }
    }

    /**
     * @notice This function allows the owner to remove a vault from the RayFi protocol
     * @dev To remove a vault, we only need to reset its id, rather than all the data related to it
     * This is because the `s_vaultTokens` array will be left with a gap and if the same vault is added again,
     * it will be assigned a new id, which is the next available index in the `s_vaultTokens`
     * @param vaultToken The key of the vault to remove
     */
    function removeVault(address vaultToken) external onlyOwner {
        uint256 vaultId = s_vaults[vaultToken].vaultId;
        if (vaultId <= 0) {
            revert RayFi__VaultDoesNotExist(vaultToken);
        } else {
            delete s_vaultTokens[vaultId - 1];
            delete s_vaults[vaultToken].vaultId;
        }
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
            s_totalRewardShares -= balanceOf(user);
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
        address oldRouter = address(s_router);
        s_router = IUniswapV2Router02(newRouter);
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
     * @param newSwapReceiver The address of the new swap receiver
     */
    function setSwapReceiver(address newSwapReceiver) external onlyOwner {
        if (newSwapReceiver == address(0)) {
            revert RayFi__CannotSetToZeroAddress();
        }
        address oldSwapReceiver = s_swapReceiver;
        s_swapReceiver = newSwapReceiver;
        emit SwapReceiverUpdated(newSwapReceiver, oldSwapReceiver);
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
        return s_totalStakedShares;
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
        uint256 newBalance = balanceOf(shareholder);
        if (newBalance >= s_minimumTokenBalanceForRewards && !s_isExcludedFromRewards[shareholder]) {
            (bool success, uint256 oldBalance) = s_shareholders.tryGet(shareholder);
            if (!success) {
                s_totalRewardShares += newBalance;
            } else {
                s_totalRewardShares += newBalance - oldBalance;
            }
            s_shareholders.set(shareholder, newBalance);
        } else {
            s_shareholders.remove(shareholder);
            s_totalRewardShares -= newBalance;
        }
    }

    /**
     * @dev Low-level function to stake RayFi tokens
     * Assumes that `_balances` have already been updated and that the vault exists
     * @param user The address of the user to stake the RayFi tokens for
     * @param value The amount of RayFi tokens to stake
     */
    function _stake(address vaultToken, address user, uint256 value) private {
        uint256 position = s_vaults[vaultToken].positions[user];
        if (position == 0) {
            position = s_vaults[vaultToken].users.length;
            s_vaults[vaultToken].users.push(user);
        }

        s_vaults[vaultToken].vaultBalances[user] += value;
        s_vaults[vaultToken].totalVaultShares += value;
        s_stakedBalances[user] += value;
        s_totalStakedShares += value;

        emit RayFiStaked(user, value, s_totalStakedShares);
    }

    /**
     * @dev Low-level function to unstake RayFi tokens
     * @param user The address of the user to unstake the RayFi tokens for
     * @param value The amount of RayFi tokens to unstake
     */
    function _unstake(address vaultToken, address user, uint256 value) private {
        s_vaults[vaultToken].vaultBalances[user] -= value;
        s_vaults[vaultToken].totalVaultShares -= value;
        s_stakedBalances[user] -= value;
        s_totalStakedShares -= value;

        if (s_vaults[vaultToken].vaultBalances[user] <= 0) {
            Vault storage vault = s_vaults[vaultToken];
            uint256 userIndex = vault.positions[user] - 1;
            uint256 lastIndex = vault.users.length - 1;
            if (userIndex != lastIndex) {
                address lastUser = vault.users[lastIndex];
                vault.users[userIndex] = lastUser;
                vault.positions[lastUser] = userIndex;
            }
            vault.users.pop();
            delete vault.positions[user];
        }

        emit RayFiUnstaked(user, value, s_totalStakedShares);
    }

    /**
     * @dev Low-level function to swap the reward token using a UniswapV2-compatible router
     * Assumes that the tokens have already been approved for spending
     * @param router The address of the UniswapV2-compatible router
     * @param tokenIn The address of the token to swap from
     * @param tokenOut The address of the token to swap to
     * @param to The address to send the swapped tokens to
     * @param amountIn The amount of tokens to swap from
     * @param slippage The maximum acceptable percentage slippage for the swap
     */
    function _swapRewards(
        IUniswapV2Router02 router,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amountIn,
        uint8 slippage
    ) private {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint256 amountOutMin = router.getAmountsOut(amountIn, path)[1];
        if (slippage >= 1) {
            amountOutMin = amountOutMin * (100 - slippage) / 100;
        }
        router.swapExactTokensForTokens(amountIn, amountOutMin, path, to, block.timestamp);
    }

    /**
     * @dev Low-level function to process the given vaults
     * Mainly exists to clean up the high-level `distributeRewards` function and void stack-too-deep errors
     * @param vaultTokens The list of vaults to distribute rewards to
     * @param rewardToken The address of the reward token
     * @param totalRewardsToReinvest The total amount of rewards to reinvest
     * @param totalStakedShares The total amount of RayFi staked in the contract
     * @param slippage The maximum acceptable percentage slippage for the swaps
     * @param gasForRewards The amount of gas to use for processing rewards in stateful mode
     * @param isStateful Whether to save the state of the distribution
     */
    function _runVaultLoop(
        address[] memory vaultTokens,
        address rewardToken,
        uint256 totalRewardsToReinvest,
        uint256 totalStakedShares,
        uint8 slippage,
        uint32 gasForRewards,
        bool isStateful
    ) private {
        IUniswapV2Router02 router = s_router;
        ERC20(rewardToken).approve(address(s_router), totalRewardsToReinvest);

        address swapReceiver = s_swapReceiver;
        for (uint256 i; i < vaultTokens.length; ++i) {
            address vaultToken = vaultTokens[i];

            uint256 totalStakedAmountInVault = s_vaults[vaultToken].totalVaultShares;
            if (totalStakedAmountInVault <= 0) {
                continue;
            }

            uint256 rewardsToReinvest = totalRewardsToReinvest * totalStakedAmountInVault / totalStakedShares;
            uint256 vaultTokensToDistribute;
            if (vaultToken == address(this)) {
                _swapRewards(router, rewardToken, vaultToken, swapReceiver, rewardsToReinvest, slippage);
                vaultTokensToDistribute = ERC20(vaultToken).balanceOf(swapReceiver);
            } else {
                _swapRewards(router, rewardToken, vaultToken, address(this), rewardsToReinvest, slippage);
                vaultTokensToDistribute = ERC20(vaultToken).balanceOf(address(this));
            }

            uint256 magnifiedVaultTokensPerShare =
                _calculateRewardPerShare(vaultTokensToDistribute, totalStakedAmountInVault);

            _processVault(gasForRewards, magnifiedVaultTokensPerShare, vaultToken, isStateful);
        }
    }

    /**
     * @dev Low-level function to process rewards for all token holders in either stateful or stateless mode
     * @param gasForRewards The amount of gas to use for processing rewards
     * @param magnifiedRewardPerShare The magnified reward amount per share
     * @param rewardToken The address of the reward token
     * @param isStateful Whether to save the state of the distribution
     */
    function _processRewards(
        uint32 gasForRewards,
        uint256 magnifiedRewardPerShare,
        address rewardToken,
        bool isStateful
    ) private {
        uint256 shareholderCount = s_shareholders.length();
        if (isStateful) {
            _runRewardLoopStateFul(gasForRewards, shareholderCount, magnifiedRewardPerShare, 0);
        } else {
            uint256 withdrawnRewards;
            for (uint256 i; i < shareholderCount; ++i) {
                (address user,) = s_shareholders.at(i);
                withdrawnRewards += _processRewardOfUserStateless(user, magnifiedRewardPerShare, rewardToken);
            }

            emit RewardsDistributed(withdrawnRewards, 0);
        }
    }

    /**
     * @dev Low-level function to process rewards a specific vault in either stateful or stateless mode
     * @param gasForRewards The amount of gas to use for processing rewards
     * @param magnifiedVaultTokensPerShare The magnified reward amount per share
     * @param vaultToken The address of the vault token
     * @param isStateful Whether to save the state of the distribution
     */
    function _processVault(
        uint32 gasForRewards,
        uint256 magnifiedVaultTokensPerShare,
        address vaultToken,
        bool isStateful
    ) private {
        address[] memory vaultUsers = s_vaults[vaultToken].users;
        uint256 userCount = vaultUsers.length;
        if (isStateful) {
            _runRewardLoopStateFul(gasForRewards, userCount, magnifiedVaultTokensPerShare, 0);
        } else {
            uint256 withdrawnRewards;
            for (uint256 i; i < userCount; ++i) {
                withdrawnRewards +=
                    _processVaultOfUserStateless(vaultUsers[i], magnifiedVaultTokensPerShare, vaultToken);
            }

            if (vaultToken == address(this)) {
                super._update(s_swapReceiver, address(this), withdrawnRewards);
                s_totalStakedShares += withdrawnRewards;
            } else {
                s_vaults[vaultToken].totalVaultShares += withdrawnRewards;
            }

            emit RewardsDistributed(0, withdrawnRewards);
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
        uint32 gasForRewards,
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
     */
    function _processRewardOfUserStateless(address user, uint256 magnifiedRewardPerShare, address rewardToken)
        private
        returns (uint256 withdrawableReward)
    {
        withdrawableReward = _calculateReward(magnifiedRewardPerShare, balanceOf(user));
        if (withdrawableReward >= 1) {
            ERC20(rewardToken).transfer(user, withdrawableReward);
        }
    }

    /**
     * @notice Processes rewards for a specific token holder for a specific vault
     * @param user The address of the token holder
     * @param magnifiedVaultTokensPerShare The magnified reward amount per share
     * @param vaultToken The address of the vault token
     */
    function _processVaultOfUserStateless(address user, uint256 magnifiedVaultTokensPerShare, address vaultToken)
        private
        returns (uint256 withdrawableReward)
    {
        withdrawableReward = _calculateReward(magnifiedVaultTokensPerShare, s_vaults[vaultToken].vaultBalances[user]);
        if (withdrawableReward >= 1) {
            if (vaultToken != address(this)) {
                ERC20(vaultToken).transfer(user, withdrawableReward);
            } else {
                unchecked {
                    s_stakedBalances[user] += withdrawableReward;
                }
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

            super._update(s_swapReceiver, address(this), reinvestableRayFi);
            // _stake(user, reinvestableRayFi);

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
