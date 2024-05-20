// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployRayFi} from "../../script/DeployRayFi.s.sol";
import {RayFi, Ownable, EnumerableMap} from "../../src/RayFi.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract RayFiTest is Test {
    RayFi rayFi;
    ERC20Mock rewardToken;
    IUniswapV2Router02 router;

    uint256 public constant DECIMALS = 18;
    uint256 public constant MAX_SUPPLY = 10_000_000 ether;
    uint256 public constant INITIAL_RAYFI_LIQUIDITY = 2_858_550 ether;
    uint256 public constant INITIAL_REWARD_LIQUIDITY = 14_739 ether;
    uint256 public constant TRANSFER_AMOUNT = 10_000 ether;
    uint72 public constant MINIMUM_TOKEN_BALANCE_FOR_REWARDS = 1_000 ether;
    uint32 public constant GAS_FOR_REWARDS = 1_000_000;
    uint16 public constant USER_COUNT = 100;
    uint8 public constant MAX_ATTEMPTS = 100;
    uint8 public constant ACCEPTED_PRECISION_LOSS = 1;
    uint8 public constant BUY_FEE = 4;
    uint8 public constant SELL_FEE = 4;

    string public constant TOKEN_NAME = "RayFi";
    string public constant TOKEN_SYMBOL = "RAYFI";

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address SWAP_RECEIVER = makeAddr("rewardReceiver");
    address DUMMY_ADDRESS = makeAddr("dummy");

    address[USER_COUNT] users;

    function setUp() external {
        DeployRayFi deployRayFi = new DeployRayFi();
        (rayFi, rewardToken, router) = deployRayFi.run(FEE_RECEIVER, SWAP_RECEIVER);

        for (uint256 i; i < USER_COUNT; ++i) {
            users[i] = makeAddr(string(abi.encode("user", i)));
        }
    }

    modifier liquidityAdded() {
        vm.startPrank(msg.sender);
        rewardToken.mint(msg.sender, INITIAL_REWARD_LIQUIDITY);

        rayFi.approve(address(router), INITIAL_RAYFI_LIQUIDITY);
        rewardToken.approve(address(router), INITIAL_REWARD_LIQUIDITY);

        router.addLiquidity(
            address(rayFi),
            address(rewardToken),
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_REWARD_LIQUIDITY,
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_REWARD_LIQUIDITY,
            address(this),
            block.timestamp
        );

        address pair = IUniswapV2Factory(router.factory()).getPair(address(rayFi), address(rewardToken));
        rayFi.setAutomatedMarketPair(pair, true);
        rayFi.setIsExcludedFromRewards(pair, true);
        vm.stopPrank();
        _;
    }

    modifier feesSet() {
        vm.startPrank(msg.sender);
        rayFi.setFeeAmounts(BUY_FEE, SELL_FEE);
        vm.stopPrank();
        _;
    }

    modifier minimumBalanceForRewardsSet() {
        vm.startPrank(msg.sender);
        rayFi.setMinimumTokenBalanceForRewards(MINIMUM_TOKEN_BALANCE_FOR_REWARDS);
        vm.stopPrank();
        _;
    }

    modifier fundUserBase() {
        uint256 balance = rayFi.balanceOf(msg.sender);
        vm.startPrank(msg.sender);
        for (uint256 i; i < USER_COUNT; ++i) {
            rayFi.transfer(users[i], balance / (USER_COUNT + 1));
        }
        vm.stopPrank();
        _;
    }

    modifier fullyStakeUserBase() {
        for (uint256 i; i < USER_COUNT; ++i) {
            vm.startPrank(users[i]);
            rayFi.stake(address(rayFi), rayFi.balanceOf(users[i]));
            vm.stopPrank();
        }
        _;
    }

    modifier partiallyStakeUserBase() {
        for (uint256 i; i < USER_COUNT; ++i) {
            vm.startPrank(users[i]);
            rayFi.stake(address(rayFi), rayFi.balanceOf(users[i]) / 2);
            vm.stopPrank();
        }
        _;
    }

    /////////////////////////
    // Constructor Tests ////
    /////////////////////////

    function testRevertsOnZeroAddressArguments() public {
        vm.expectRevert(RayFi.RayFi__CannotSetToZeroAddress.selector);
        new RayFi(address(0), address(0), address(0), address(0));
    }

    function testERC20WasInitializedCorrectly() public view {
        assertEq(rayFi.name(), TOKEN_NAME);
        assertEq(rayFi.symbol(), TOKEN_SYMBOL);
        assertEq(rayFi.decimals(), DECIMALS);
        assertEq(rayFi.totalSupply(), MAX_SUPPLY);
    }

    function testRayFiWasInitializedCorrectly() public view {
        assertEq(address(rayFi.owner()), msg.sender);
        assertEq(rayFi.balanceOf(msg.sender), rayFi.totalSupply());
        assertEq(rayFi.getTotalRewardShares(), MAX_SUPPLY);
        assertEq(rayFi.getFeeReceiver(), FEE_RECEIVER);
    }

    //////////////////////
    // Transfer Tests ////
    //////////////////////

    function testTransferWorksAndTakesFees() public feesSet {
        vm.prank(msg.sender);
        rayFi.transfer(address(this), TRANSFER_AMOUNT);

        uint256 feeAmount = TRANSFER_AMOUNT * (BUY_FEE + SELL_FEE) / 100;
        assertEq(rayFi.balanceOf(address(this)), TRANSFER_AMOUNT - feeAmount);
        assertEq(rayFi.balanceOf(FEE_RECEIVER), feeAmount);
    }

    function testTransferToFeeExemptAddressWorks() public feesSet {
        vm.startPrank(msg.sender);
        rayFi.setIsFeeExempt(address(this), true);
        rayFi.transfer(address(this), TRANSFER_AMOUNT);
        vm.stopPrank();

        assertEq(rayFi.balanceOf(address(this)), TRANSFER_AMOUNT);
        assertEq(rayFi.balanceOf(FEE_RECEIVER), 0);
    }

    function testTransferFromWorksAndTakesFees() public feesSet {
        vm.prank(msg.sender);
        rayFi.approve(address(this), TRANSFER_AMOUNT);

        rayFi.transferFrom(msg.sender, address(this), TRANSFER_AMOUNT);

        uint256 feeAmount = TRANSFER_AMOUNT * (BUY_FEE + SELL_FEE) / 100;
        assertEq(rayFi.balanceOf(address(this)), TRANSFER_AMOUNT - feeAmount);
        assertEq(rayFi.balanceOf(FEE_RECEIVER), feeAmount);
    }

    function testTransfersUpdateShareholdersSet() public minimumBalanceForRewardsSet {
        // 1. Check new shareholders are added correctly and balances are updated
        vm.startPrank(msg.sender);
        rayFi.transfer(address(this), TRANSFER_AMOUNT);

        address[] memory shareholders = rayFi.getShareholders();
        assertEq(shareholders.length, 2);
        assertEq(shareholders[0], msg.sender);
        assertEq(shareholders[1], address(this));
        assertEq(rayFi.getSharesBalanceOf(msg.sender), MAX_SUPPLY - TRANSFER_AMOUNT);
        assertEq(rayFi.getSharesBalanceOf(address(this)), TRANSFER_AMOUNT);

        // 2. Check existing shareholders are updated correctly and balances are updated
        rayFi.transfer(address(this), TRANSFER_AMOUNT);

        shareholders = rayFi.getShareholders();
        assertEq(shareholders.length, 2);
        assertEq(shareholders[0], msg.sender);
        assertEq(shareholders[1], address(this));
        assertEq(rayFi.getSharesBalanceOf(msg.sender), MAX_SUPPLY - TRANSFER_AMOUNT * 2);
        assertEq(rayFi.getSharesBalanceOf(address(this)), TRANSFER_AMOUNT * 2);
        vm.stopPrank();

        // 3. Check existing shareholders are removed if their balance goes below the minimum
        rayFi.transfer(msg.sender, TRANSFER_AMOUNT * 2);

        shareholders = rayFi.getShareholders();
        assertEq(shareholders.length, 1);
        assertEq(shareholders[0], msg.sender);
        assertEq(rayFi.getSharesBalanceOf(msg.sender), MAX_SUPPLY);
        assertEq(rayFi.getSharesBalanceOf(address(this)), 0);
    }

    function testTradingFeesRemovalWorks() public feesSet {
        vm.startPrank(msg.sender);
        rayFi.removeTradingFees();
        rayFi.transfer(address(this), TRANSFER_AMOUNT);

        assertEq(rayFi.balanceOf(address(this)), TRANSFER_AMOUNT);
    }

    function testCanRetrieveERC20FromContract() public {
        rewardToken.mint(address(rayFi), TRANSFER_AMOUNT);

        vm.prank(msg.sender);
        rayFi.retrieveERC20(address(rewardToken), address(this), TRANSFER_AMOUNT);

        assertEq(rewardToken.balanceOf(address(this)), TRANSFER_AMOUNT);
    }

    function testCanRetrieveBNBFromContract() public {
        vm.deal(address(rayFi), TRANSFER_AMOUNT);

        vm.prank(msg.sender);
        rayFi.retrieveBNB(DUMMY_ADDRESS, TRANSFER_AMOUNT);

        assertEq(DUMMY_ADDRESS.balance, TRANSFER_AMOUNT);
    }

    function testCannotRetrieveRayFiFromContract() public {
        vm.expectRevert(abi.encodeWithSelector(RayFi.RayFi__CannotRetrieveRayFi.selector));
        vm.prank(msg.sender);
        rayFi.retrieveERC20(address(rayFi), address(this), TRANSFER_AMOUNT);
    }

    function testCannotTransferToRayFiContract() public {
        vm.expectRevert(abi.encodeWithSelector(RayFi.RayFi__CannotManuallySendRayFiToTheContract.selector));
        vm.prank(msg.sender);
        rayFi.transfer(address(rayFi), TRANSFER_AMOUNT);
    }

    function testTransferRevertsWhenInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, TRANSFER_AMOUNT)
        );
        rayFi.transfer(DUMMY_ADDRESS, TRANSFER_AMOUNT);
    }

    function testTransferFromRevertsWhenInsufficientAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, TRANSFER_AMOUNT)
        );
        rayFi.transferFrom(msg.sender, DUMMY_ADDRESS, TRANSFER_AMOUNT);
    }

    function testTransferRevertsWhenInvalidSender() public {
        vm.startPrank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        rayFi.transfer(DUMMY_ADDRESS, TRANSFER_AMOUNT);
        vm.stopPrank();
    }

    function testTransferRevertsWhenInvalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        rayFi.transfer(address(0), TRANSFER_AMOUNT);
    }

    //////////////////
    // Swap Tests ////
    //////////////////

    function testSwapsWork() public liquidityAdded {
        // 1. Test sell swap
        address[] memory path = new address[](2);
        path[0] = address(rayFi);
        path[1] = address(rewardToken);
        uint256 amountIn = TRANSFER_AMOUNT;
        uint256 amountOut = router.getAmountOut(amountIn, INITIAL_RAYFI_LIQUIDITY, INITIAL_REWARD_LIQUIDITY);
        uint256 rewardBalanceBefore = rewardToken.balanceOf(msg.sender);

        vm.startPrank(msg.sender);
        rayFi.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut, path, msg.sender, block.timestamp
        );

        assertEq(rewardToken.balanceOf(msg.sender), rewardBalanceBefore + amountOut);

        // 2. Test buy swap
        path[0] = address(rewardToken);
        path[1] = address(rayFi);
        amountIn = amountOut;
        (uint112 rewardLiquidity, uint112 rayFiLiquidity,) = IUniswapV2Pair(
            IUniswapV2Factory(router.factory()).getPair(address(rayFi), address(rewardToken))
        ).getReserves();
        amountOut = router.getAmountOut(amountIn, rewardLiquidity, rayFiLiquidity);
        uint256 rayFiBalanceBefore = rayFi.balanceOf(msg.sender);

        rewardToken.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut, path, msg.sender, block.timestamp
        );
        vm.stopPrank();

        assertEq(rayFi.balanceOf(msg.sender), rayFiBalanceBefore + amountOut);
    }

    function testSwapsTakeFees() public liquidityAdded feesSet {
        // 1. Test sell fee
        address[] memory path = new address[](2);
        path[0] = address(rayFi);
        path[1] = address(rewardToken);
        uint256 amountIn = TRANSFER_AMOUNT;
        uint256 feeAmount = amountIn * SELL_FEE / 100;
        uint256 adjustedAmountIn = amountIn - feeAmount;
        uint256 amountOut = router.getAmountOut(adjustedAmountIn, INITIAL_RAYFI_LIQUIDITY, INITIAL_REWARD_LIQUIDITY);
        uint256 rewardBalanceBefore = rewardToken.balanceOf(msg.sender);

        vm.startPrank(msg.sender);
        rayFi.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut, path, msg.sender, block.timestamp
        );

        assertEq(rewardToken.balanceOf(msg.sender), rewardBalanceBefore + amountOut);
        assertEq(rayFi.balanceOf(FEE_RECEIVER), feeAmount);

        // 2. Test buy fee
        path[0] = address(rewardToken);
        path[1] = address(rayFi);
        amountIn = amountOut;
        (uint112 rewardLiquidity, uint112 rayFiLiquidity,) = IUniswapV2Pair(
            IUniswapV2Factory(router.factory()).getPair(address(rayFi), address(rewardToken))
        ).getReserves();
        amountOut = router.getAmountOut(amountIn, rewardLiquidity, rayFiLiquidity);
        feeAmount = amountOut * BUY_FEE / 100;
        uint256 adjustedAmountOut = amountOut - feeAmount;
        uint256 rayFiBalanceBefore = rayFi.balanceOf(msg.sender);
        uint256 feeReceiverRayFiBalanceBefore = rayFi.balanceOf(FEE_RECEIVER);

        rewardToken.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, adjustedAmountOut, path, msg.sender, block.timestamp
        );
        vm.stopPrank();

        assertEq(rayFi.balanceOf(msg.sender), rayFiBalanceBefore + adjustedAmountOut);
        assertEq(rayFi.balanceOf(FEE_RECEIVER), feeReceiverRayFiBalanceBefore + feeAmount);
    }

    /////////////////////
    // Staking Tests ////
    /////////////////////

    function testUsersCanStake() public minimumBalanceForRewardsSet {
        uint256 balanceBefore = rayFi.balanceOf(msg.sender);
        uint256 totalRewardSharesBefore = rayFi.getTotalRewardShares();

        vm.recordLogs();
        vm.prank(msg.sender);
        rayFi.stake(address(rayFi), TRANSFER_AMOUNT);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[1].topics[0], keccak256("RayFiStaked(address,uint256,uint256)"));
        assertEq(entries[1].topics[1], bytes32(uint256(uint160(msg.sender))));
        assertEq(entries[1].topics[2], bytes32(TRANSFER_AMOUNT));
        assertEq(entries[1].topics[3], bytes32(TRANSFER_AMOUNT));
        assertEq(rayFi.getStakedBalanceOf(msg.sender), TRANSFER_AMOUNT);
        assertEq(rayFi.balanceOf(msg.sender), balanceBefore - TRANSFER_AMOUNT);
        assertEq(rayFi.balanceOf(address(rayFi)), TRANSFER_AMOUNT);
        assertEq(rayFi.getTotalStakedShares(), TRANSFER_AMOUNT);
        assertEq(rayFi.getTotalRewardShares(), totalRewardSharesBefore);
        assertEq(rayFi.getSharesBalanceOf(msg.sender), balanceBefore);
    }

    function testStakingRevertsOnInsufficientInput() public minimumBalanceForRewardsSet {
        vm.expectRevert(
            abi.encodeWithSelector(RayFi.RayFi__InsufficientTokensToStake.selector, MINIMUM_TOKEN_BALANCE_FOR_REWARDS)
        );
        rayFi.stake(address(rayFi), 0);
    }

    function testStakingRevertsOnInexistentVault() public minimumBalanceForRewardsSet {
        vm.expectRevert(abi.encodeWithSelector(RayFi.RayFi__VaultDoesNotExist.selector, address(0)));
        vm.prank(msg.sender);
        rayFi.stake(address(0), TRANSFER_AMOUNT);
    }

    function testStakingRevertsOnInsufficientBalance() public minimumBalanceForRewardsSet {
        vm.prank(msg.sender);
        rayFi.transfer(address(this), TRANSFER_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), TRANSFER_AMOUNT, TRANSFER_AMOUNT + 1
            )
        );
        rayFi.stake(address(rayFi), TRANSFER_AMOUNT + 1);
    }

    function testUsersCanUnstake() public minimumBalanceForRewardsSet {
        uint256 balanceBefore = rayFi.balanceOf(msg.sender);
        vm.startPrank(msg.sender);
        rayFi.transfer(address(this), TRANSFER_AMOUNT);
        rayFi.stake(address(rayFi), TRANSFER_AMOUNT);
        vm.stopPrank();
        rayFi.stake(address(rayFi), TRANSFER_AMOUNT);

        vm.recordLogs();
        vm.startPrank(msg.sender);
        rayFi.unstake(address(rayFi), TRANSFER_AMOUNT / 2);
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("RayFiUnstaked(address,uint256,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(msg.sender))));
        assertEq(entries[0].topics[2], bytes32(TRANSFER_AMOUNT / 2));
        assertEq(entries[0].topics[3], bytes32(TRANSFER_AMOUNT + TRANSFER_AMOUNT / 2));
        assertEq(rayFi.getStakedBalanceOf(msg.sender), TRANSFER_AMOUNT / 2);
        assertEq(rayFi.balanceOf(msg.sender), balanceBefore - TRANSFER_AMOUNT - TRANSFER_AMOUNT / 2);
        assertEq(rayFi.balanceOf(address(rayFi)), TRANSFER_AMOUNT + TRANSFER_AMOUNT / 2);
        assertEq(rayFi.getTotalStakedShares(), TRANSFER_AMOUNT + TRANSFER_AMOUNT / 2);
        assertEq(rayFi.getSharesBalanceOf(msg.sender), balanceBefore - TRANSFER_AMOUNT);

        vm.recordLogs();
        rayFi.unstake(address(rayFi), TRANSFER_AMOUNT);

        entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("RayFiUnstaked(address,uint256,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(address(this)))));
        assertEq(entries[0].topics[2], bytes32(TRANSFER_AMOUNT));
        assertEq(entries[0].topics[3], bytes32(TRANSFER_AMOUNT / 2));
        assertEq(rayFi.getStakedBalanceOf(address(this)), 0);
        assertEq(rayFi.balanceOf(address(this)), TRANSFER_AMOUNT);
        assertEq(rayFi.balanceOf(address(rayFi)), TRANSFER_AMOUNT / 2);
        assertEq(rayFi.getTotalStakedShares(), TRANSFER_AMOUNT / 2);
        assertEq(rayFi.getSharesBalanceOf(address(this)), TRANSFER_AMOUNT);
    }

    function testUnstakingRevertsOnInsufficientStakedBalance() public minimumBalanceForRewardsSet {
        vm.prank(msg.sender);
        rayFi.transfer(address(this), TRANSFER_AMOUNT / 2);
        rayFi.stake(address(rayFi), TRANSFER_AMOUNT / 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                RayFi.RayFi__InsufficientStakedBalance.selector, TRANSFER_AMOUNT / 2, TRANSFER_AMOUNT
            )
        );
        rayFi.unstake(address(rayFi), TRANSFER_AMOUNT);
    }

    function testVaultsCanBeAdded() public {
        vm.startPrank(msg.sender);
        rayFi.addVault(address(this));

        rayFi.stake(address(this), TRANSFER_AMOUNT);
        vm.stopPrank();

        assertEq(rayFi.getStakedBalanceOf(msg.sender), TRANSFER_AMOUNT);
    }

    function testCannotAddExistingVaults() public {
        vm.startPrank(msg.sender);
        rayFi.addVault(address(this));

        vm.expectRevert(abi.encodeWithSelector(RayFi.RayFi__VaultAlreadyExists.selector, address(this)));
        rayFi.addVault(address(this));
    }

    function testCannotAddZeroAddressVaults() public {
        vm.expectRevert(abi.encodeWithSelector(RayFi.RayFi__CannotSetToZeroAddress.selector));
        vm.prank(msg.sender);
        rayFi.addVault(address(0));
    }

    function testVaultsCanBeRemoved() public fundUserBase fullyStakeUserBase {
        uint256[USER_COUNT] memory stakedBalancesBefore;
        for (uint256 i; i < USER_COUNT; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }

        vm.startPrank(msg.sender);
        rayFi.addVault(address(this));
        rayFi.removeVault(address(rayFi));

        vm.expectRevert(abi.encodeWithSelector(RayFi.RayFi__VaultDoesNotExist.selector, address(rayFi)));
        rayFi.stake(address(rayFi), TRANSFER_AMOUNT);

        for (uint256 i; i < USER_COUNT; ++i) {
            assertEq(rayFi.getStakedBalanceOf(users[i]), 0);
            assertEq(rayFi.balanceOf(users[i]), stakedBalancesBefore[i]);
        }
    }

    function testCannotRemoveInexistentVaults() public {
        vm.expectRevert(abi.encodeWithSelector(RayFi.RayFi__VaultDoesNotExist.selector, address(0)));
        vm.prank(msg.sender);
        rayFi.removeVault(address(0));
    }

    function testCannotAddOrRemoveVaultsDuringDistributions() public fundUserBase {
        rewardToken.mint(address(rayFi), TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 2}(GAS_FOR_REWARDS, 0, new address[](0));

        vm.expectRevert(RayFi.RayFi__DistributionInProgress.selector);
        rayFi.addVault(address(this));

        vm.expectRevert(RayFi.RayFi__DistributionInProgress.selector);
        rayFi.removeVault(address(rayFi));
    }

    ////////////////////
    // Reward Tests ////
    ////////////////////

    function testStatelessDistributionWorksForMultipleUsers() public minimumBalanceForRewardsSet fundUserBase {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);

        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();

        for (uint256 i; i < USER_COUNT; ++i) {
            assert(rewardToken.balanceOf(users[i]) >= TRANSFER_AMOUNT / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS);
        }
        assert(rewardToken.balanceOf(msg.sender) >= TRANSFER_AMOUNT / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS);
    }

    function testStatelessDistributionEmitsEvents() public {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);

        vm.recordLogs();
        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[1].topics[0], keccak256("RewardsDistributed(uint256,address)"));
        assert(entries[1].topics[1] >= bytes32(TRANSFER_AMOUNT - ACCEPTED_PRECISION_LOSS));
        assertEq(entries[1].topics[2], bytes32(uint256(uint160(address(rewardToken)))));
    }

    function testStatelessReinvestmentWorksForMultipleUsers()
        public
        liquidityAdded
        minimumBalanceForRewardsSet
        fundUserBase
        fullyStakeUserBase
    {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);
        rayFi.stake(address(rayFi), rayFi.balanceOf(msg.sender));

        uint256[USER_COUNT] memory stakedBalancesBefore;
        for (uint256 i; i < USER_COUNT; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }
        uint256 stakedBalanceBeforeOwner = rayFi.getStakedBalanceOf(msg.sender);

        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
            );
        }
        assert(
            rayFi.getStakedBalanceOf(msg.sender)
                >= stakedBalanceBeforeOwner + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
        );
    }

    function testStatelessReinvestmentEmitsEvents() public liquidityAdded {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);
        rayFi.stake(address(rayFi), rayFi.balanceOf(msg.sender));

        vm.recordLogs();
        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        assertEq(entries[6].topics[0], keccak256("RewardsReinvested(uint256,address)"));
        assert(entries[6].topics[1] >= bytes32(amountOut - ACCEPTED_PRECISION_LOSS));
        assertEq(entries[6].topics[2], bytes32(uint256(uint160(address(rayFi)))));
    }

    function testStatelessDistributionAndReinvestmentWorksForMultipleUsers()
        public
        liquidityAdded
        minimumBalanceForRewardsSet
        fundUserBase
        partiallyStakeUserBase
    {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);
        rayFi.stake(address(rayFi), rayFi.balanceOf(msg.sender));

        uint256[USER_COUNT] memory stakedBalancesBefore;
        for (uint256 i; i < USER_COUNT; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }
        uint256 stakedBalanceBeforeOwner = rayFi.getStakedBalanceOf(msg.sender);

        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / ((USER_COUNT + 1) * 2) - ACCEPTED_PRECISION_LOSS
            );
        }
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rewardToken.balanceOf(users[i]) >= TRANSFER_AMOUNT / ((USER_COUNT + 1) * 2) - ACCEPTED_PRECISION_LOSS
            );
        }
        assert(
            rayFi.getStakedBalanceOf(msg.sender)
                >= stakedBalanceBeforeOwner + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
        );
    }

    function testStatefulDistributionWorksForMultipleUsers() public minimumBalanceForRewardsSet fundUserBase {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);

        for (uint256 i; i < MAX_ATTEMPTS; ++i) {
            if (rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 2}(GAS_FOR_REWARDS, 0, new address[](0))) {
                break;
            }
        }
        vm.stopPrank();

        for (uint256 i; i < USER_COUNT; ++i) {
            assert(rewardToken.balanceOf(users[i]) >= TRANSFER_AMOUNT / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS);
        }
    }

    function testStatefulDistributionEmitsEvents() public {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);

        vm.recordLogs();
        rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 2}(GAS_FOR_REWARDS, 0, new address[](0));
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("RewardsDistributed(uint256,address)"));
        assert(entries[2].topics[1] >= bytes32(TRANSFER_AMOUNT - ACCEPTED_PRECISION_LOSS));
        assertEq(entries[2].topics[2], bytes32(uint256(uint160(address(rewardToken)))));
    }

    function testStatefulReinvestmentWorksForMultipleUsers()
        public
        liquidityAdded
        minimumBalanceForRewardsSet
        fundUserBase
        fullyStakeUserBase
    {
        rewardToken.mint(address(rayFi), TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rayFi.stake(address(rayFi), rayFi.balanceOf(msg.sender));

        uint256[USER_COUNT] memory stakedBalancesBefore;
        for (uint256 i; i < USER_COUNT; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }
        uint256 stakedBalanceBeforeOwner = rayFi.getStakedBalanceOf(msg.sender);

        for (uint256 i; i < MAX_ATTEMPTS; ++i) {
            if (rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 10}(GAS_FOR_REWARDS, 0, new address[](0))) {
                break;
            }
        }
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
            );
        }
        assert(
            rayFi.getStakedBalanceOf(msg.sender)
                >= stakedBalanceBeforeOwner + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
        );
    }

    function testStatefulDistributionAndReinvestmentWorksForMultipleUsers()
        public
        liquidityAdded
        minimumBalanceForRewardsSet
        fundUserBase
        partiallyStakeUserBase
    {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);
        rayFi.stake(address(rayFi), rayFi.balanceOf(msg.sender));

        uint256[USER_COUNT] memory stakedBalancesBefore;
        for (uint256 i; i < USER_COUNT; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }
        uint256 stakedBalanceBeforeOwner = rayFi.getStakedBalanceOf(msg.sender);

        vm.startPrank(msg.sender);
        for (uint256 i; i < MAX_ATTEMPTS; ++i) {
            if (rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 10}(GAS_FOR_REWARDS, 0, new address[](0))) {
                break;
            }
        }
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / ((USER_COUNT + 1) * 2) - ACCEPTED_PRECISION_LOSS
            );
        }
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rewardToken.balanceOf(users[i]) >= TRANSFER_AMOUNT / ((USER_COUNT + 1) * 2) - ACCEPTED_PRECISION_LOSS
            );
        }
        assert(
            rayFi.getStakedBalanceOf(msg.sender)
                >= stakedBalanceBeforeOwner + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
        );
    }

    function testTransferDuringStatefulDistributionAndReinvestmentForMultipleUsers()
        public
        liquidityAdded
        minimumBalanceForRewardsSet
        fundUserBase
        partiallyStakeUserBase
    {
        rewardToken.mint(address(rayFi), TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rayFi.stake(address(rayFi), rayFi.balanceOf(msg.sender) / 2);

        uint256[USER_COUNT] memory stakedBalancesBefore;
        for (uint256 i; i < USER_COUNT; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }

        vm.startPrank(msg.sender);
        rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 10}(GAS_FOR_REWARDS, 0, new address[](0));

        for (uint256 i = 10; i < 20; ++i) {
            vm.startPrank(users[i]);
            rayFi.transfer(users[i + 70], TRANSFER_AMOUNT / 10);
            vm.stopPrank();
        }

        vm.startPrank(msg.sender);
        for (uint256 i; i < MAX_ATTEMPTS; ++i) {
            if (rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 10}(GAS_FOR_REWARDS, 0, new address[](0))) {
                break;
            }
        }
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT / 2, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
            );
            assert(rewardToken.balanceOf(users[i]) >= TRANSFER_AMOUNT / 2 / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS);
        }
    }

    function testStatelessDistributionRevertsIfStatefulDistributionIsInProgress() public fundUserBase {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);

        rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 2}(GAS_FOR_REWARDS, 0, new address[](0));

        vm.expectRevert(RayFi.RayFi__DistributionInProgress.selector);
        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();
    }

    function testStakingIsDisabledDuringDistribution() public liquidityAdded fundUserBase {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);
        rayFi.stake(address(rayFi), TRANSFER_AMOUNT);

        rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 2}(GAS_FOR_REWARDS, 0, new address[](0));

        vm.expectRevert(RayFi.RayFi__DistributionInProgress.selector);
        rayFi.stake(address(rayFi), TRANSFER_AMOUNT);
        vm.expectRevert(RayFi.RayFi__DistributionInProgress.selector);
        rayFi.unstake(address(rayFi), TRANSFER_AMOUNT);
        vm.stopPrank();
    }

    function testDistributionToSpecificVaultWorks() public liquidityAdded minimumBalanceForRewardsSet {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);
        rayFi.stake(address(rayFi), rayFi.balanceOf(msg.sender));

        address[] memory vaults = new address[](1);
        vaults[0] = address(rayFi);
        rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 2}(GAS_FOR_REWARDS, 0, vaults);
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        assert(rayFi.getStakedBalanceOf(msg.sender) >= TRANSFER_AMOUNT + amountOut - ACCEPTED_PRECISION_LOSS);
    }

    function testReinvetmentWithNonZeroSlippageWorks() public liquidityAdded minimumBalanceForRewardsSet {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);
        rayFi.stake(address(rayFi), rayFi.balanceOf(msg.sender));

        rayFi.distributeRewardsStateless(5);
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        assert(rayFi.getStakedBalanceOf(msg.sender) >= TRANSFER_AMOUNT + amountOut - ACCEPTED_PRECISION_LOSS);
    }

    function testOnlyOwnerCanStartDistribution() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFi.distributeRewardsStateless(0);
    }

    function testStatefulDistributionRevertsOnInsufficientGas() public liquidityAdded {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);

        vm.expectRevert();
        rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS / 2}(GAS_FOR_REWARDS, 0, new address[](0));

        rayFi.stake(address(rayFi), rayFi.balanceOf(msg.sender));

        vm.expectRevert();
        rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS / 2}(GAS_FOR_REWARDS, 0, new address[](0));
        vm.stopPrank();
    }

    function testEmptyVaultsDoNotBreakDistribution() public liquidityAdded {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFi), TRANSFER_AMOUNT);
        rayFi.stake(address(rayFi), rayFi.balanceOf(msg.sender));

        address[] memory vaults = new address[](2);
        vaults[0] = address(0);
        vaults[1] = address(rayFi);
        rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 2}(GAS_FOR_REWARDS, 0, vaults);
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        assert(rayFi.getStakedBalanceOf(msg.sender) >= TRANSFER_AMOUNT + amountOut - ACCEPTED_PRECISION_LOSS);
    }

    ////////////////////
    // Setter Tests ////
    ////////////////////

    function testSetFeeAmounts() public {
        // Set valid fee amounts
        vm.startPrank(msg.sender);
        vm.recordLogs();
        rayFi.setFeeAmounts(BUY_FEE, SELL_FEE);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("FeeAmountsUpdated(uint8,uint8)"));
        (uint8 buyFee, uint8 sellFee) = abi.decode(entries[0].data, (uint8, uint8));
        assertEq(buyFee, BUY_FEE);
        assertEq(sellFee, SELL_FEE);
        assertEq(rayFi.getBuyFee(), BUY_FEE);
        assertEq(rayFi.getSellFee(), SELL_FEE);

        // Revert when total fee exceeds maximum
        buyFee = 99;
        sellFee = 99;
        vm.expectRevert(abi.encodeWithSelector(RayFi.RayFi__FeesTooHigh.selector, buyFee + sellFee));
        rayFi.setFeeAmounts(buyFee, sellFee);
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFi.setFeeAmounts(BUY_FEE, SELL_FEE);
    }

    function testSetMinimumTokenBalanceForRewards() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        rayFi.setMinimumTokenBalanceForRewards(MINIMUM_TOKEN_BALANCE_FOR_REWARDS);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("MinimumTokenBalanceForRewardsUpdated(uint256,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(MINIMUM_TOKEN_BALANCE_FOR_REWARDS)));
        assertEq(entries[0].topics[2], bytes32(0));
        assertEq(rayFi.getMinimumTokenBalanceForRewards(), MINIMUM_TOKEN_BALANCE_FOR_REWARDS);
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFi.setMinimumTokenBalanceForRewards(MINIMUM_TOKEN_BALANCE_FOR_REWARDS);
    }

    function testSetIsExcludedFromRewards() public {
        vm.prank(msg.sender);
        rayFi.transfer(address(this), TRANSFER_AMOUNT);
        rayFi.stake(address(rayFi), TRANSFER_AMOUNT);

        // Test valid call
        vm.recordLogs();
        vm.startPrank(msg.sender);
        rayFi.setIsExcludedFromRewards(address(this), true);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("IsUserExcludedFromRewardsUpdated(address,bool)"));
        assertEq(entries[2].topics[1], bytes32(uint256(uint160(address(this)))));
        assertEq(entries[2].topics[2], bytes32(uint256(1)));
        assertEq(rayFi.getShareholders().length, 1);
        assertEq(rayFi.balanceOf(address(this)), TRANSFER_AMOUNT);

        rayFi.setIsExcludedFromRewards(address(this), false);
        vm.stopPrank();

        assertEq(rayFi.getShareholders().length, 2);

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFi.setIsExcludedFromRewards(address(this), false);
    }

    function testSetRewardToken() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newRewardToken = address(DUMMY_ADDRESS);
        rayFi.setRewardToken(newRewardToken);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("RewardTokenUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newRewardToken))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(address(rewardToken)))));
        assertEq(rayFi.getRewardToken(), newRewardToken);

        // Revert when zero address is passed as input
        vm.expectRevert(RayFi.RayFi__CannotSetToZeroAddress.selector);
        rayFi.setRewardToken(address(0));
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFi.setRewardToken(newRewardToken);
    }

    function testSetRouter() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newRouter = address(DUMMY_ADDRESS);
        rayFi.setRouter(newRouter);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("RouterUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newRouter))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(address(router)))));

        // Revert when zero address is passed as input
        vm.expectRevert(RayFi.RayFi__CannotSetToZeroAddress.selector);
        rayFi.setRouter(address(0));
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFi.setRouter(newRouter);
    }

    function testSetFeeReceiver() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newFeeReceiver = address(DUMMY_ADDRESS);
        rayFi.setFeeReceiver(newFeeReceiver);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("FeeReceiverUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newFeeReceiver))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(FEE_RECEIVER))));
        assertEq(rayFi.getFeeReceiver(), newFeeReceiver);

        // Revert when zero address is passed as input
        vm.expectRevert(RayFi.RayFi__CannotSetToZeroAddress.selector);
        rayFi.setFeeReceiver(address(0));
        vm.stopPrank();

        // Revert when called by non-msg.sender
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFi.setFeeReceiver(newFeeReceiver);
    }

    function testSetSwapReceiver() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newSwapReceiver = address(DUMMY_ADDRESS);
        rayFi.setSwapReceiver(newSwapReceiver);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("SwapReceiverUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newSwapReceiver))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(SWAP_RECEIVER))));

        // Revert when zero address is passed as input
        vm.expectRevert(RayFi.RayFi__CannotSetToZeroAddress.selector);
        rayFi.setSwapReceiver(address(0));
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFi.setSwapReceiver(newSwapReceiver);
    }
}
