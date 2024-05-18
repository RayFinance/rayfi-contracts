// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title RayFi
 * @author 0xC4LL3
 * @notice This contract is the underlying token of the Ray Finance ecosystem.
 * @notice The primary purpose of this token is acquiring (or selling) shares of the Ray Finance protocol.
 */
contract RayFi is ERC20, Ownable {
    //////////////
    // Types    //
    //////////////

    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using Checkpoints for Checkpoints.Trace160;

    enum DistributionState {
        Inactive,
        ProcessingVaults,
        ProcessingRewards
    }

    enum VaultState {
        Ready,
        Processing,
        ResetPending
    }

    struct Vault {
        uint256 vaultId;
        uint256 totalVaultShares;
        uint256 magnifiedRewardPerShare;
        uint256 lastProcessedIndex;
        EnumerableMap.AddressToUintMap stakers;
        VaultState state;
    }

    /////////////////////
    // State Variables //
    /////////////////////

    uint256 private constant MAGNITUDE = type(uint128).max;
    uint128 private constant MAX_SUPPLY = 10_000_000 ether;
    uint8 private constant MAX_FEES = 10;

    uint256 private s_totalStakedShares;
    uint256 private s_totalRewardShares;
    uint256 private s_magnifiedRewardPerShare;
    uint256 private s_lastProcessedIndex;
    uint128 private s_minimumTokenBalanceForRewards;
    uint96 private s_snapshotId;

    IUniswapV2Router02 private s_router;

    address private s_rewardToken;
    address private s_swapReceiver;
    address private s_feeReceiver;

    uint8 private s_buyFee;
    uint8 private s_sellFee;

    bool private s_areTradingFeesEnabled = true;

    mapping(address user => bool isExemptFromFees) private s_isFeeExempt;
    mapping(address user => bool isExcludedFromRewards) private s_isExcludedFromRewards;
    mapping(address pair => bool isAMMPair) private s_automatedMarketMakerPairs;
    mapping(address user => uint256 amountStaked) private s_stakedBalances;
    mapping(address user => Checkpoints.Trace160 balanceSnapshot) private s_balancesSnapshots;
    mapping(address token => Vault vault) private s_vaults;

    address[] private s_vaultTokens;

    EnumerableMap.AddressToUintMap private s_shareholders;

    DistributionState private s_distributionState;

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
     * @notice Emitted when a snapshot is taken
     * @param snapshotId The id of the snapshot
     */
    event SnapshotTaken(uint96 indexed snapshotId);

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
    error RayFi__CannotManuallySendRayFiToTheContract();

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
     * @dev Triggered when trying to retrieve RayFi tokens from the contract
     * This is a security measure to prevent malicious retrieval of RayFi tokens
     */
    error RayFi__CannotRetrieveRayFi();

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
     * @notice Indicates a failure in staking tokens due to not having enough tokens
     * @param minimumTokenBalance The minimum amount of tokens required to stake
     */
    error RayFi__InsufficientTokensToStake(uint256 minimumTokenBalance);

    /**
     * @dev Triggered when trying to process rewards, but not enough gas was sent with the transaction
     * @param gasRequested The amount of gas requested
     * @param gasProvided The amount of gas provided
     */
    error RayFi__InsufficientGas(uint256 gasRequested, uint256 gasProvided);

    /**
     * @dev Triggered when trying to alter the state of the distribution while it is already in progress
     */
    error RayFi__DistributionInProgress();

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

        s_isExcludedFromRewards[feeReceiver] = true;
        s_isExcludedFromRewards[swapReceiver] = true;
        s_isExcludedFromRewards[address(this)] = true;
        s_isExcludedFromRewards[address(0)] = true;

        s_vaultTokens.push(address(this));
        s_vaults[address(this)].vaultId = s_vaultTokens.length;

        _mint(msg.sender, MAX_SUPPLY);
    }

    ///////////////////////////
    // External Functions    //
    ///////////////////////////

    /**
     * @notice This function allows users to stake their RayFi tokens to have their rewards reinvested in RayFi
     * @param value The amount of tokens to stake
     */
    function stake(address vault, uint256 value) external {
        if (!s_shareholders.contains(msg.sender)) {
            revert RayFi__InsufficientTokensToStake(s_minimumTokenBalanceForRewards);
        } else if (s_vaults[vault].vaultId <= 0) {
            revert RayFi__VaultDoesNotExist(vault);
        } else if (s_distributionState != DistributionState.Inactive) {
            revert RayFi__DistributionInProgress();
        }

        super._update(msg.sender, address(this), value);
        _stake(vault, msg.sender, value);
        _updateShareholder(msg.sender, s_balancesSnapshots[msg.sender], uint160(value), s_snapshotId, _sub);
    }

    /**
     * @notice This function allows users to unstake their RayFi tokens
     * @dev We do not check if the vault exists so that users may withdraw from a vault that has been removed
     * @param value The amount of tokens to unstake
     */
    function unstake(address vault, uint256 value) external {
        uint256 stakedBalance = s_vaults[vault].stakers.get(msg.sender);
        if (stakedBalance < value) {
            revert RayFi__InsufficientStakedBalance(stakedBalance, value);
        } else if (s_distributionState != DistributionState.Inactive) {
            revert RayFi__DistributionInProgress();
        }

        _unstake(vault, msg.sender, value);
        super._update(address(this), msg.sender, value);
        _updateShareholder(msg.sender, s_balancesSnapshots[msg.sender], uint160(value), s_snapshotId, _add);
    }

    /**
     * @notice High-level function to start the reward distribution process in stateless mode
     * The stateless mode is always the preferred one, as it is drastically more gas-efficient
     * Rewards are either sent to users as stablecoins or reinvested into RayFi for users who have staked their tokens
     * @param maxSwapSlippage The maximum acceptable percentage slippage for the swaps
     * @param vaultTokens The list of vaults to distribute rewards to, can be left empty to distribute to all vaults
     */
    function distributeRewardsStateless(uint8 maxSwapSlippage, address[] memory vaultTokens) external onlyOwner {
        if (s_distributionState != DistributionState.Inactive) {
            revert RayFi__DistributionInProgress();
        }

        address rewardToken = s_rewardToken;
        uint256 totalUnclaimedRewards = ERC20(rewardToken).balanceOf(address(this));
        if (totalUnclaimedRewards <= 0) {
            revert RayFi__NothingToDistribute();
        }

        uint256 totalRewardShares = s_totalRewardShares;
        uint256 totalStakedShares = s_totalStakedShares;
        if (totalStakedShares >= 1) {
            if (vaultTokens.length <= 0) {
                vaultTokens = s_vaultTokens;
            }

            uint256 totalRewardsToReinvest = totalUnclaimedRewards * totalStakedShares / totalRewardShares;
            _processVaults(
                vaultTokens, rewardToken, totalRewardsToReinvest, totalStakedShares, maxSwapSlippage, 0, false
            );

            uint256 totalNonStakedAmount = totalRewardShares - totalStakedShares;
            if (totalNonStakedAmount >= 1) {
                totalUnclaimedRewards = ERC20(rewardToken).balanceOf(address(this));
                uint256 magnifiedRewardPerShare = _calculateRewardPerShare(totalUnclaimedRewards, totalNonStakedAmount);
                _processRewards(0, magnifiedRewardPerShare, rewardToken, false);
            }
        } else {
            uint256 magnifiedRewardPerShare = _calculateRewardPerShare(totalUnclaimedRewards, totalRewardShares);
            _processRewards(0, magnifiedRewardPerShare, rewardToken, false);
        }
    }

    /**
     * @notice High-level function to start the reward distribution process in stateful mode
     * The stateful mode is a backup to use only in case the stateless mode is unable to complete the distribution
     * Rewards are either sent to users as stablecoins or reinvested into RayFi for users who have staked their tokens
     * @param gasForRewards The amount of gas to use for processing rewards
     * This is a safety mechanism to prevent the contract from running out of gas at an inconvenient time
     * `gasForRewards` should be set to a value that is less than the gas limit of the transaction
     * @param maxSwapSlippage The maximum acceptable percentage slippage for the swaps
     * @param vaultTokens The list of vaults to distribute rewards to, can be left empty to distribute to all vaults
     */
    function distributeRewardsStateful(uint32 gasForRewards, uint8 maxSwapSlippage, address[] memory vaultTokens)
        external
        onlyOwner
        returns (bool isComplete)
    {
        address rewardToken = s_rewardToken;
        uint256 totalUnclaimedRewards = ERC20(rewardToken).balanceOf(address(this));
        bool isDistributionInactive = s_distributionState == DistributionState.Inactive;
        if (isDistributionInactive) {
            if (totalUnclaimedRewards <= 0) {
                revert RayFi__NothingToDistribute();
            } else {
                _snapshot();
            }
        }

        uint256 totalRewardShares = s_totalRewardShares;
        uint256 totalStakedShares = s_totalStakedShares;
        if (totalStakedShares >= 1) {
            if (vaultTokens.length <= 0) {
                vaultTokens = s_vaultTokens;
            }

            uint256 totalRewardsToReinvest;
            if (isDistributionInactive) {
                totalRewardsToReinvest = totalUnclaimedRewards * totalStakedShares / totalRewardShares;
                s_distributionState = DistributionState.ProcessingVaults;
            }

            if (s_distributionState == DistributionState.ProcessingVaults) {
                isComplete = _processVaults(
                    vaultTokens,
                    rewardToken,
                    totalRewardsToReinvest,
                    totalStakedShares,
                    maxSwapSlippage,
                    gasForRewards,
                    true
                );
                if (!isComplete) {
                    return false;
                }
            }

            uint256 totalNonStakedAmount = totalRewardShares - totalStakedShares;
            if (totalNonStakedAmount >= 1) {
                if (s_distributionState != DistributionState.ProcessingRewards) {
                    totalUnclaimedRewards = ERC20(rewardToken).balanceOf(address(this));
                    s_magnifiedRewardPerShare = _calculateRewardPerShare(totalUnclaimedRewards, totalNonStakedAmount);
                    s_distributionState = DistributionState.ProcessingRewards;
                }
                isComplete = _processRewards(gasForRewards, s_magnifiedRewardPerShare, rewardToken, true);
            }
        } else {
            if (isDistributionInactive) {
                s_magnifiedRewardPerShare = _calculateRewardPerShare(totalUnclaimedRewards, totalRewardShares);
                s_distributionState = DistributionState.ProcessingRewards;
            }
            isComplete = _processRewards(gasForRewards, s_magnifiedRewardPerShare, rewardToken, true);
        }

        if (isComplete) {
            s_magnifiedRewardPerShare = 0;
            s_distributionState = DistributionState.Inactive;
        }
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
     * @notice This function allows the owner to retrieve any ERC20 token other than RayFi stuck in the contract
     * @dev Retrieving RayFi tokens is not allowed both because they cannot be manually transferred to the contract
     * and to prevent malicious retrieval of staked RayFi tokens in case the owner wallet is compromised
     * @param token The address of the token to retrieve
     * @param to The address to send the tokens to
     * @param value The amount of tokens to retrieve
     */
    function retrieveERC20(address token, address to, uint256 value) external onlyOwner {
        if (token == address(this)) {
            revert RayFi__CannotRetrieveRayFi();
        }
        ERC20(token).transfer(to, value);
    }

    /**
     * @notice This function allows the owner to retrieve BNB stuck in the contract
     * @param to The address to send the BNB to
     * @param value The amount of BNB to retrieve
     */
    function retrieveBNB(address to, uint256 value) external onlyOwner {
        payable(to).transfer(value);
    }

    /**
     * @notice This function allows the owner to permanently disable trading fees on the RayFi token
     * @dev This is a one-way function and cannot be undone
     */
    function removeTradingFees() external onlyOwner {
        s_areTradingFeesEnabled = false;
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
    function setMinimumTokenBalanceForRewards(uint128 newMinimum) external onlyOwner {
        uint128 oldMinimum = s_minimumTokenBalanceForRewards;
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
        if (isExcluded) {
            _removeShareholder(user, s_balancesSnapshots[user], s_snapshotId);
        } else {
            _updateShareholder(user, s_balancesSnapshots[user], uint160(balanceOf(user)), s_snapshotId, _add);
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
     * @notice Get the total amount of tokens eligible for rewards
     * @return The total reward tokens amount
     */
    function getTotalRewardShares() external view returns (uint256) {
        return s_totalRewardShares;
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
            revert RayFi__CannotManuallySendRayFiToTheContract();
        }

        if (s_areTradingFeesEnabled) {
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
        }

        super._update(from, to, value);

        uint96 snapshotId = s_snapshotId;
        _updateShareholder(from, s_balancesSnapshots[from], uint160(value), snapshotId, _sub);
        _updateShareholder(to, s_balancesSnapshots[to], uint160(value), snapshotId, _add);
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
    }

    /**
     * @dev Updates the shareholder list based on the new balance
     * @param shareholder The address of the shareholder
     */
    function _updateShareholder(
        address shareholder,
        Checkpoints.Trace160 storage balanceSnapshot,
        uint160 delta,
        uint96 snapshotId,
        function(uint160, uint160) pure returns(uint160) operation
    ) private {
        uint256 newBalance = balanceOf(shareholder);
        uint256 totalBalance = newBalance + s_stakedBalances[shareholder];
        if (totalBalance >= s_minimumTokenBalanceForRewards && !s_isExcludedFromRewards[shareholder]) {
            (bool success, uint256 oldBalance) = s_shareholders.tryGet(shareholder);
            if (!success) {
                s_totalRewardShares += totalBalance;
            } else {
                s_totalRewardShares = s_totalRewardShares + totalBalance - oldBalance;
            }
            s_shareholders.set(shareholder, totalBalance);
            balanceSnapshot.push(snapshotId, operation(balanceSnapshot.latest(), delta));
        } else {
            _removeShareholder(shareholder, balanceSnapshot, snapshotId);
        }
    }

    /**
     * @dev Removes a shareholder from the list and retrieves their staked tokens
     * @param shareholder The address of the shareholder
     */
    function _removeShareholder(address shareholder, Checkpoints.Trace160 storage balanceSnapshot, uint96 snapshotId)
        private
    {
        if (s_shareholders.contains(shareholder)) {
            s_totalRewardShares -= s_shareholders.get(shareholder);
            s_shareholders.remove(shareholder);
            uint256 stakedBalance = s_stakedBalances[shareholder];
            if (stakedBalance >= 1) {
                for (uint256 i; i < s_vaultTokens.length; ++i) {
                    address vaultToken = s_vaultTokens[i];
                    _unstake(vaultToken, shareholder, s_vaults[vaultToken].stakers.get(shareholder));
                }
                super._update(address(this), shareholder, stakedBalance);
            }
            balanceSnapshot.push(snapshotId, 0);
        }
    }

    /**
     * @dev Low-level function to stake RayFi tokens
     * Assumes that `_balances` have already been updated and that the vault exists
     * @param user The address of the user to stake the RayFi tokens for
     * @param value The amount of RayFi tokens to stake
     */
    function _stake(address vaultToken, address user, uint256 value) private {
        Vault storage vault = s_vaults[vaultToken];
        (, uint256 userBalance) = vault.stakers.tryGet(user);
        vault.stakers.set(user, userBalance + value);
        vault.totalVaultShares += value;

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
        Vault storage vault = s_vaults[vaultToken];
        uint256 userBalance = vault.stakers.get(user);
        uint256 remainingBalance = userBalance - value;
        if (remainingBalance <= 0) {
            vault.stakers.remove(user);
        } else {
            vault.stakers.set(user, remainingBalance);
        }
        vault.totalVaultShares -= value;

        s_stakedBalances[user] -= value;
        s_totalStakedShares -= value;

        emit RayFiUnstaked(user, value, s_totalStakedShares);
    }

    function _snapshot() private returns (uint96 currentSnapshot) {
        currentSnapshot = ++s_snapshotId;
        emit SnapshotTaken(currentSnapshot);
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
    ) private returns (bool isComplete) {
        uint256 shareholderCount = s_shareholders.length();
        uint256 earnedRewards;
        if (isStateful) {
            uint256 startingGas = gasleft();
            if (gasForRewards >= startingGas) {
                revert RayFi__InsufficientGas(gasForRewards, startingGas);
            }

            uint256 lastProcessedIndex = s_lastProcessedIndex;
            uint256 gasUsed;
            while (gasUsed < gasForRewards) {
                (address user,) = s_shareholders.at(lastProcessedIndex);
                earnedRewards += _processRewardOfUser(
                    user,
                    magnifiedRewardPerShare,
                    s_balancesSnapshots[user].upperLookupRecent(s_snapshotId - 1),
                    rewardToken
                );

                ++lastProcessedIndex;
                if (lastProcessedIndex >= shareholderCount) {
                    lastProcessedIndex = 0;
                    isComplete = true;
                    break;
                }

                gasUsed += startingGas - gasleft();
            }
            s_lastProcessedIndex = lastProcessedIndex;
        } else {
            for (uint256 i; i < shareholderCount; ++i) {
                (address user,) = s_shareholders.at(i);
                earnedRewards += _processRewardOfUser(user, magnifiedRewardPerShare, balanceOf(user), rewardToken);
            }
            isComplete = true;
        }

        emit RewardsDistributed(earnedRewards, 0);
    }

    /**
     * @dev Low-level function to process the given vaults
     * Mainly exists to clean up the high-level `distributeRewards` function and void stack-too-deep errors
     * We do all swaps first to make it easier to resume the distribution in case it is stateful
     * @param vaultTokens The list of vaults to distribute rewards to
     * @param rewardToken The address of the reward token
     * @param totalRewardsToReinvest The total amount of rewards to reinvest
     * @param totalStakedShares The total amount of RayFi staked in the contract
     * @param slippage The maximum acceptable percentage slippage for the swaps
     * @param gasForRewards The amount of gas to use for processing rewards in stateful mode
     * @param isStateful Whether to save the state of the distribution
     * @return isComplete Whether the distribution is complete
     */
    function _processVaults(
        address[] memory vaultTokens,
        address rewardToken,
        uint256 totalRewardsToReinvest,
        uint256 totalStakedShares,
        uint8 slippage,
        uint32 gasForRewards,
        bool isStateful
    ) private returns (bool isComplete) {
        address swapReceiver = s_swapReceiver;

        if (totalRewardsToReinvest >= 1) {
            IUniswapV2Router02 router = s_router;
            ERC20(rewardToken).approve(address(s_router), totalRewardsToReinvest);

            for (uint256 i; i < vaultTokens.length; ++i) {
                address vaultToken = vaultTokens[i];
                uint256 totalStakedAmountInVault = s_vaults[vaultToken].totalVaultShares;
                if (totalStakedAmountInVault <= 0) {
                    continue;
                }

                uint256 rewardsToReinvest = totalRewardsToReinvest * totalStakedAmountInVault / totalStakedShares;
                if (vaultToken != address(this)) {
                    _swapRewards(router, rewardToken, vaultToken, address(this), rewardsToReinvest, slippage);
                } else {
                    _swapRewards(router, rewardToken, vaultToken, swapReceiver, rewardsToReinvest, slippage);
                }
            }
        }

        for (uint256 i; i < vaultTokens.length; ++i) {
            address vaultToken = vaultTokens[i];
            Vault storage vault = s_vaults[vaultToken];
            uint256 totalStakedAmountInVault = vault.totalVaultShares;
            VaultState startingVaultState = vault.state;
            if (totalStakedAmountInVault <= 0 || startingVaultState == VaultState.ResetPending) {
                continue;
            }

            uint256 vaultTokensToDistribute;
            if (vaultToken != address(this)) {
                vaultTokensToDistribute = ERC20(vaultToken).balanceOf(address(this));
            } else {
                vaultTokensToDistribute = balanceOf(swapReceiver);
            }

            uint256 magnifiedVaultRewardsPerShare;
            if (isStateful) {
                if (startingVaultState != VaultState.Processing) {
                    vault.magnifiedRewardPerShare =
                        _calculateRewardPerShare(vaultTokensToDistribute, totalStakedAmountInVault);
                    vault.state = VaultState.Processing;
                }
                magnifiedVaultRewardsPerShare = vault.magnifiedRewardPerShare;
            } else {
                magnifiedVaultRewardsPerShare =
                    _calculateRewardPerShare(vaultTokensToDistribute, totalStakedAmountInVault);
            }

            if (_processVault(gasForRewards, magnifiedVaultRewardsPerShare, vaultToken, isStateful)) {
                vault.magnifiedRewardPerShare = 0;
                vault.state = VaultState.ResetPending;
                continue;
            } else {
                return false;
            }
        }

        if (isStateful) {
            for (uint256 i; i < vaultTokens.length; ++i) {
                s_vaults[vaultTokens[i]].state = VaultState.Ready;
            }
        }
        return true;
    }

    /**
     * @dev Low-level function to process rewards a specific vault in either stateful or stateless mode
     * @param gasForRewards The amount of gas to use for processing rewards
     * @param magnifiedVaultRewardsPerShare The magnified reward amount per share
     * @param vaultToken The address of the vault token
     * @param isStateful Whether to save the state of the distribution
     */
    function _processVault(
        uint32 gasForRewards,
        uint256 magnifiedVaultRewardsPerShare,
        address vaultToken,
        bool isStateful
    ) private returns (bool isComplete) {
        Vault storage vault = s_vaults[vaultToken];
        uint256 shareholderCount = vault.stakers.length();
        uint256 vaultRewards;
        if (isStateful) {
            uint256 startingGas = gasleft();
            if (gasForRewards >= startingGas) {
                revert RayFi__InsufficientGas(gasForRewards, startingGas);
            }

            uint256 lastProcessedIndex = vault.lastProcessedIndex;
            uint256 gasUsed;
            while (gasUsed < gasForRewards) {
                (address user,) = vault.stakers.at(lastProcessedIndex);
                vaultRewards += _processVaultOfUser(user, magnifiedVaultRewardsPerShare, vaultToken, vault);

                ++lastProcessedIndex;
                if (lastProcessedIndex >= shareholderCount) {
                    lastProcessedIndex = 0;
                    isComplete = true;
                    break;
                }

                gasUsed += startingGas - gasleft();
            }
            vault.lastProcessedIndex = lastProcessedIndex;
        } else {
            for (uint256 i; i < shareholderCount; ++i) {
                (address user,) = vault.stakers.at(i);
                vaultRewards += _processVaultOfUser(user, magnifiedVaultRewardsPerShare, vaultToken, vault);
            }
            isComplete = true;
        }

        if (vaultToken == address(this)) {
            super._update(s_swapReceiver, address(this), vaultRewards);
            vault.totalVaultShares += vaultRewards;
            s_totalStakedShares += vaultRewards;
            s_totalRewardShares += vaultRewards;
        }

        emit RewardsDistributed(0, vaultRewards);
    }

    /**
     * @notice Processes rewards for a specific token holder
     * @param user The address of the token holder
     * @param magnifiedRewardPerShare The magnified reward amount per share
     * @param rewardToken The address of the reward token
     * @return earnedReward The amount of rewards withdrawn
     */
    function _processRewardOfUser(address user, uint256 magnifiedRewardPerShare, uint256 balance, address rewardToken)
        private
        returns (uint256 earnedReward)
    {
        earnedReward = _calculateReward(magnifiedRewardPerShare, balance);
        if (earnedReward >= 1) {
            ERC20(rewardToken).transfer(user, earnedReward);
        }
    }

    /**
     * @notice Processes rewards for a specific token holder for a specific vault
     * @param user The address of the token holder
     * @param magnifiedVaultRewardsPerShare The magnified reward amount per share
     * @param vaultToken The address of the vault token
     * @param vault The storage pointer to the vault
     * @return vaultReward The amount of rewards withdrawn
     */
    function _processVaultOfUser(
        address user,
        uint256 magnifiedVaultRewardsPerShare,
        address vaultToken,
        Vault storage vault
    ) private returns (uint256 vaultReward) {
        uint256 vaultBalanceOfUser = vault.stakers.get(user);
        vaultReward = _calculateReward(magnifiedVaultRewardsPerShare, vaultBalanceOfUser);
        if (vaultReward >= 1) {
            if (vaultToken != address(this)) {
                ERC20(vaultToken).transfer(user, vaultReward);
            } else {
                unchecked {
                    vault.stakers.set(user, vaultBalanceOfUser + vaultReward);
                    s_stakedBalances[user] += vaultReward;
                }
            }
        }
    }

    ///////////////////////////////
    // Private Pure Functions    //
    ///////////////////////////////

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
     * @dev In each distribution, there is a small amount of stablecoins not distributed,
     * the magnified amount of which is `(amount * MAGNITUDE) % totalShares`
     * With a well-chosen `MAGNITUDE`, this amount (de-magnified) can be less than 1 wei
     * We could actually keep track of the undistributed stablecoins for the next distribution,
     * but keeping track of such data on-chain costs much more than the saved stablecoins, so we do not do that
     * @param totalRewards The total amount of rewards
     * @param totalShares The total amount of shares
     * @return The magnified amount of reward per share
     */
    function _calculateRewardPerShare(uint256 totalRewards, uint256 totalShares) private pure returns (uint256) {
        return totalRewards * MAGNITUDE / totalShares;
    }

    /**
     * @dev Low-level function to add two numbers used as a function argument for updating balance snapshots
     * @param a The first number
     * @param b The second number
     * @return The sum of the two numbers
     */
    function _add(uint160 a, uint160 b) private pure returns (uint160) {
        return a + b;
    }

    /**
     * @dev Low-level function to subtract two numbers used as a function argument for updating balance snapshots
     * @param a The first number
     * @param b The second number
     * @return The difference of the two numbers
     */
    function _sub(uint160 a, uint160 b) private pure returns (uint160) {
        return a - b;
    }
}
