// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployRayFiToken} from "../../script/DeployRayFiToken.s.sol";
import {RayFiToken, Ownable, EnumerableMap} from "../../src/RayFiToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract RayFiTokenTest is Test {
    RayFiToken rayFiToken;
    ERC20Mock rewardToken;
    IUniswapV2Router02 router;

    uint256 public constant DECIMALS = 18;
    uint256 public constant MAX_SUPPLY = 10_000_000 * (10 ** DECIMALS);
    uint256 public constant INITIAL_RAYFI_LIQUIDITY = 2_858_550 * (10 ** DECIMALS);
    uint256 public constant INITIAL_DIVIDEND_LIQUIDITY = 14_739 * (10 ** DECIMALS);
    uint256 public constant TRANSFER_AMOUNT = 10_000 * (10 ** DECIMALS);
    uint256 public constant MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS = 1_000 * (10 ** DECIMALS);
    uint32 public constant GAS_FOR_DIVIDENDS = 1_000_000;
    uint16 public constant USER_COUNT = 100;
    uint8 public constant ACCEPTED_PRECISION_LOSS = 1;
    uint8 public constant BUY_FEE = 4;
    uint8 public constant SELL_FEE = 4;

    string public constant TOKEN_NAME = "RayFi";
    string public constant TOKEN_SYMBOL = "RAYFI";

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address DIVIDEND_RECEIVER = makeAddr("rewardReceiver");
    address DUMMY_ADDRESS = makeAddr("dummy");

    address[USER_COUNT] users;

    function setUp() external {
        DeployRayFiToken deployRayFiToken = new DeployRayFiToken();
        (rayFiToken, rewardToken, router) = deployRayFiToken.run(FEE_RECEIVER, DIVIDEND_RECEIVER);

        for (uint256 i; i < USER_COUNT; ++i) {
            users[i] = makeAddr(string(abi.encode("user", i)));
        }
    }

    modifier liquidityAdded() {
        vm.startPrank(msg.sender);
        rewardToken.mint(msg.sender, INITIAL_DIVIDEND_LIQUIDITY);

        rayFiToken.approve(address(router), INITIAL_RAYFI_LIQUIDITY);
        rewardToken.approve(address(router), INITIAL_DIVIDEND_LIQUIDITY);

        router.addLiquidity(
            address(rayFiToken),
            address(rewardToken),
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_DIVIDEND_LIQUIDITY,
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_DIVIDEND_LIQUIDITY,
            address(this),
            block.timestamp
        );

        address pair = IUniswapV2Factory(router.factory()).getPair(address(rayFiToken), address(rewardToken));
        rayFiToken.setAutomatedMarketPair(pair, true);
        rayFiToken.setIsExcludedFromRewards(pair, true);
        vm.stopPrank();
        _;
    }

    modifier feesSet() {
        vm.startPrank(msg.sender);
        rayFiToken.setFeeAmounts(BUY_FEE, SELL_FEE);
        vm.stopPrank();
        _;
    }

    modifier minimumBalanceForRewardsSet() {
        vm.startPrank(msg.sender);
        rayFiToken.setMinimumTokenBalanceForRewards(MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS);
        vm.stopPrank();
        _;
    }

    modifier fundUserBase() {
        uint256 balance = rayFiToken.balanceOf(msg.sender);
        vm.startPrank(msg.sender);
        for (uint256 i; i < USER_COUNT; ++i) {
            rayFiToken.transfer(users[i], balance / (USER_COUNT + 1));
        }
        vm.stopPrank();
        _;
    }

    modifier fullyStakeUserBase() {
        for (uint256 i; i < USER_COUNT; ++i) {
            vm.startPrank(users[i]);
            rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(users[i]));
            vm.stopPrank();
        }
        _;
    }

    modifier partiallyStakeUserBase() {
        for (uint256 i; i < USER_COUNT; ++i) {
            vm.startPrank(users[i]);
            rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(users[i]) / 2);
            vm.stopPrank();
        }
        _;
    }

    /////////////////////////
    // Constructor Tests ////
    /////////////////////////

    function testRevertsOnZeroAddressArguments() public {
        vm.expectRevert(RayFiToken.RayFi__CannotSetToZeroAddress.selector);
        new RayFiToken(address(0), address(0), address(0), address(0));
    }

    function testERC20WasInitializedCorrectly() public view {
        assertEq(rayFiToken.name(), TOKEN_NAME);
        assertEq(rayFiToken.symbol(), TOKEN_SYMBOL);
        assertEq(rayFiToken.decimals(), DECIMALS);
        assertEq(rayFiToken.totalSupply(), MAX_SUPPLY);
    }

    function testRayFiWasInitializedCorrectly() public view {
        assertEq(address(rayFiToken.owner()), msg.sender);
        assertEq(rayFiToken.balanceOf(msg.sender), rayFiToken.totalSupply());
        assertEq(rayFiToken.getTotalRewardShares(), MAX_SUPPLY);
        assertEq(rayFiToken.getFeeReceiver(), FEE_RECEIVER);
    }

    //////////////////////
    // Transfer Tests ////
    //////////////////////

    function testTransferWorksAndTakesFees() public feesSet {
        vm.prank(msg.sender);
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);

        uint256 feeAmount = TRANSFER_AMOUNT * (BUY_FEE + SELL_FEE) / 100;
        assertEq(rayFiToken.balanceOf(address(this)), TRANSFER_AMOUNT - feeAmount);
        assertEq(rayFiToken.balanceOf(FEE_RECEIVER), feeAmount);
    }

    function testTransferToFeeExemptAddressWorks() public feesSet {
        vm.startPrank(msg.sender);
        rayFiToken.setIsFeeExempt(address(this), true);
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);
        vm.stopPrank();

        assertEq(rayFiToken.balanceOf(address(this)), TRANSFER_AMOUNT);
        assertEq(rayFiToken.balanceOf(FEE_RECEIVER), 0);
    }

    function testTransferFromWorksAndTakesFees() public feesSet {
        vm.prank(msg.sender);
        rayFiToken.approve(address(this), TRANSFER_AMOUNT);

        rayFiToken.transferFrom(msg.sender, address(this), TRANSFER_AMOUNT);

        uint256 feeAmount = TRANSFER_AMOUNT * (BUY_FEE + SELL_FEE) / 100;
        assertEq(rayFiToken.balanceOf(address(this)), TRANSFER_AMOUNT - feeAmount);
        assertEq(rayFiToken.balanceOf(FEE_RECEIVER), feeAmount);
    }

    function testTransfersUpdateShareholdersSet() public minimumBalanceForRewardsSet {
        // 1. Check new shareholders are added correctly and balances are updated
        vm.startPrank(msg.sender);
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);

        address[] memory shareholders = rayFiToken.getShareholders();
        assertEq(shareholders.length, 2);
        assertEq(shareholders[0], msg.sender);
        assertEq(shareholders[1], address(this));
        assertEq(rayFiToken.getSharesBalanceOf(msg.sender), MAX_SUPPLY - TRANSFER_AMOUNT);
        assertEq(rayFiToken.getSharesBalanceOf(address(this)), TRANSFER_AMOUNT);

        // 2. Check existing shareholders are updated correctly and balances are updated
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);

        shareholders = rayFiToken.getShareholders();
        assertEq(shareholders.length, 2);
        assertEq(shareholders[0], msg.sender);
        assertEq(shareholders[1], address(this));
        assertEq(rayFiToken.getSharesBalanceOf(msg.sender), MAX_SUPPLY - TRANSFER_AMOUNT * 2);
        assertEq(rayFiToken.getSharesBalanceOf(address(this)), TRANSFER_AMOUNT * 2);
        vm.stopPrank();

        // 3. Check existing shareholders are removed if their balance goes below the minimum
        rayFiToken.transfer(msg.sender, TRANSFER_AMOUNT * 2);

        shareholders = rayFiToken.getShareholders();
        assertEq(shareholders.length, 1);
        assertEq(shareholders[0], msg.sender);
        assertEq(rayFiToken.getSharesBalanceOf(msg.sender), MAX_SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(EnumerableMap.EnumerableMapNonexistentKey.selector, address(this)));
        rayFiToken.getSharesBalanceOf(address(this));
    }

    function testCannotTransferToRayFiContract() public {
        vm.expectRevert(abi.encodeWithSelector(RayFiToken.RayFi__CannotManuallySendRayFiTokensToTheContract.selector));
        vm.prank(msg.sender);
        rayFiToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);
    }

    function testTransferRevertsWhenInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, TRANSFER_AMOUNT)
        );
        rayFiToken.transfer(DUMMY_ADDRESS, TRANSFER_AMOUNT);
    }

    function testTransferFromRevertsWhenInsufficientAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, TRANSFER_AMOUNT)
        );
        rayFiToken.transferFrom(msg.sender, DUMMY_ADDRESS, TRANSFER_AMOUNT);
    }

    function testTransferRevertsWhenInvalidSender() public {
        vm.startPrank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        rayFiToken.transfer(DUMMY_ADDRESS, TRANSFER_AMOUNT);
        vm.stopPrank();
    }

    function testTransferRevertsWhenInvalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        rayFiToken.transfer(address(0), TRANSFER_AMOUNT);
    }

    //////////////////
    // Swap Tests ////
    //////////////////

    function testSwapsWork() public liquidityAdded {
        // 1. Test buy swap
        address[] memory path = new address[](2);
        path[0] = address(rayFiToken);
        path[1] = address(rewardToken);
        uint256 amountIn = TRANSFER_AMOUNT;
        uint256 amountOut = router.getAmountOut(amountIn, INITIAL_RAYFI_LIQUIDITY, INITIAL_DIVIDEND_LIQUIDITY);
        vm.startPrank(msg.sender);
        rayFiToken.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut, path, msg.sender, block.timestamp
        );
        assertEq(rewardToken.balanceOf(msg.sender), amountOut);

        // 2. Test sell swap
        path[0] = address(rewardToken);
        path[1] = address(rayFiToken);
        amountIn = amountOut;
        (uint112 rewardLiquidity, uint112 rayFiLiquidity,) = IUniswapV2Pair(
            IUniswapV2Factory(router.factory()).getPair(address(rayFiToken), address(rewardToken))
        ).getReserves();
        amountOut = router.getAmountOut(amountIn, rewardLiquidity, rayFiLiquidity);
        rewardToken.approve(address(router), amountIn);
        uint256 rayFiBalanceBefore = rayFiToken.balanceOf(msg.sender);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut, path, msg.sender, block.timestamp
        );
        assertEq(rayFiToken.balanceOf(msg.sender), rayFiBalanceBefore + amountOut);
        vm.stopPrank();
    }

    function testSwapsTakeFees() public liquidityAdded feesSet {
        // 1. Test buy fee
        address[] memory path = new address[](2);
        path[0] = address(rayFiToken);
        path[1] = address(rewardToken);
        uint256 amountIn = TRANSFER_AMOUNT;
        uint256 feeAmount = amountIn * BUY_FEE / 100;
        uint256 adjustedAmountIn = amountIn - feeAmount;
        uint256 amountOut = router.getAmountOut(adjustedAmountIn, INITIAL_RAYFI_LIQUIDITY, INITIAL_DIVIDEND_LIQUIDITY);
        vm.startPrank(msg.sender);
        rayFiToken.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut, path, msg.sender, block.timestamp
        );
        assertEq(rewardToken.balanceOf(msg.sender), amountOut);
        assertEq(rayFiToken.balanceOf(FEE_RECEIVER), feeAmount);

        // 2. Test sell fee
        path[0] = address(rewardToken);
        path[1] = address(rayFiToken);
        amountIn = amountOut;
        (uint112 rewardLiquidity, uint112 rayFiLiquidity,) = IUniswapV2Pair(
            IUniswapV2Factory(router.factory()).getPair(address(rayFiToken), address(rewardToken))
        ).getReserves();
        amountOut = router.getAmountOut(amountIn, rewardLiquidity, rayFiLiquidity);
        feeAmount = amountOut * SELL_FEE / 100;
        uint256 adjustedAmountOut = amountOut - feeAmount;
        rewardToken.approve(address(router), amountIn);
        uint256 rayFiBalanceBefore = rayFiToken.balanceOf(msg.sender);
        uint256 feeReceiverRayFiBalanceBefore = rayFiToken.balanceOf(FEE_RECEIVER);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, adjustedAmountOut, path, msg.sender, block.timestamp
        );
        assertEq(rayFiToken.balanceOf(msg.sender), rayFiBalanceBefore + adjustedAmountOut);
        assertEq(rayFiToken.balanceOf(FEE_RECEIVER), feeReceiverRayFiBalanceBefore + feeAmount);
        vm.stopPrank();
    }

    /////////////////////
    // Staking Tests ////
    /////////////////////

    function testUsersCanStake() public minimumBalanceForRewardsSet {
        uint256 balanceBefore = rayFiToken.balanceOf(msg.sender);
        vm.prank(msg.sender);
        vm.recordLogs();
        rayFiToken.stake(address(rayFiToken), TRANSFER_AMOUNT);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[1].topics[0], keccak256("RayFiStaked(address,uint256,uint256)"));
        assertEq(entries[1].topics[1], bytes32(uint256(uint160(msg.sender))));
        assertEq(entries[1].topics[2], bytes32(TRANSFER_AMOUNT));
        assertEq(entries[1].topics[3], bytes32(rayFiToken.getTotalStakedAmount()));
        assertEq(rayFiToken.getStakedBalanceOf(msg.sender), TRANSFER_AMOUNT);
        assertEq(rayFiToken.balanceOf(msg.sender), balanceBefore - TRANSFER_AMOUNT);
        assertEq(rayFiToken.balanceOf(address(rayFiToken)), TRANSFER_AMOUNT);
        assertEq(rayFiToken.getTotalStakedAmount(), TRANSFER_AMOUNT);
        assertEq(rayFiToken.getSharesBalanceOf(msg.sender), balanceBefore - TRANSFER_AMOUNT);
    }

    function testStakingRevertsOnInsufficientInput() public minimumBalanceForRewardsSet {
        vm.expectRevert(
            abi.encodeWithSelector(
                RayFiToken.RayFi__InsufficientTokensToStake.selector, MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS
            )
        );
        rayFiToken.stake(address(rayFiToken), 0);
    }

    function testStakingRevertsOnInexistentVault() public minimumBalanceForRewardsSet {
        vm.expectRevert(abi.encodeWithSelector(RayFiToken.RayFi__VaultDoesNotExist.selector, address(0)));
        vm.prank(msg.sender);
        rayFiToken.stake(address(0), TRANSFER_AMOUNT);
    }

    function testStakingRevertsOnInsufficientBalance() public minimumBalanceForRewardsSet {
        vm.prank(msg.sender);
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), TRANSFER_AMOUNT, TRANSFER_AMOUNT + 1
            )
        );
        rayFiToken.stake(address(rayFiToken), TRANSFER_AMOUNT + 1);
    }

    function testUsersCanUnstake() public minimumBalanceForRewardsSet {
        uint256 balanceBefore = rayFiToken.balanceOf(msg.sender);
        vm.prank(msg.sender);
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);
        rayFiToken.stake(address(rayFiToken), TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rayFiToken.stake(address(rayFiToken), TRANSFER_AMOUNT);

        vm.recordLogs();
        rayFiToken.unstake(address(rayFiToken), TRANSFER_AMOUNT);
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("RayFiUnstaked(address,uint256,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(msg.sender))));
        assertEq(entries[0].topics[2], bytes32(TRANSFER_AMOUNT));
        assertEq(entries[0].topics[3], bytes32(TRANSFER_AMOUNT));
        assertEq(rayFiToken.getStakedBalanceOf(msg.sender), 0);
        assertEq(rayFiToken.balanceOf(msg.sender), balanceBefore - TRANSFER_AMOUNT);
        assertEq(rayFiToken.balanceOf(address(rayFiToken)), TRANSFER_AMOUNT);
        assertEq(rayFiToken.getTotalStakedAmount(), TRANSFER_AMOUNT);
        assertEq(rayFiToken.getSharesBalanceOf(msg.sender), balanceBefore - TRANSFER_AMOUNT);

        vm.recordLogs();
        rayFiToken.unstake(address(rayFiToken), TRANSFER_AMOUNT);

        entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("RayFiUnstaked(address,uint256,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(address(this)))));
        assertEq(entries[0].topics[2], bytes32(TRANSFER_AMOUNT));
        assertEq(entries[0].topics[3], bytes32(0));
        assertEq(rayFiToken.getStakedBalanceOf(address(this)), 0);
        assertEq(rayFiToken.balanceOf(address(this)), TRANSFER_AMOUNT);
        assertEq(rayFiToken.balanceOf(address(rayFiToken)), 0);
        assertEq(rayFiToken.getTotalStakedAmount(), 0);
        assertEq(rayFiToken.getSharesBalanceOf(address(this)), TRANSFER_AMOUNT);
    }

    function testUnstakingRevertsOnInsufficientStakedBalance() public minimumBalanceForRewardsSet {
        vm.expectRevert(
            abi.encodeWithSelector(RayFiToken.RayFi__InsufficientStakedBalance.selector, 0, TRANSFER_AMOUNT)
        );
        rayFiToken.unstake(address(rayFiToken), TRANSFER_AMOUNT);
    }

    function testVaultsCanBeAdded() public {
        vm.startPrank(msg.sender);
        rayFiToken.addVault(address(this));

        rayFiToken.stake(address(this), TRANSFER_AMOUNT);
        vm.stopPrank();

        assertEq(rayFiToken.getStakedBalanceOf(msg.sender), TRANSFER_AMOUNT);
    }

    function testCannotAddExistingVaults() public {
        vm.startPrank(msg.sender);
        rayFiToken.addVault(address(this));

        vm.expectRevert(abi.encodeWithSelector(RayFiToken.RayFi__VaultAlreadyExists.selector, address(this)));
        rayFiToken.addVault(address(this));
    }

    function testCannotAddZeroAddressVaults() public {
        vm.expectRevert(abi.encodeWithSelector(RayFiToken.RayFi__CannotSetToZeroAddress.selector));
        vm.prank(msg.sender);
        rayFiToken.addVault(address(0));
    }

    function testVaultsCanBeRemoved() public {
        vm.startPrank(msg.sender);
        rayFiToken.removeVault(address(rayFiToken));

        vm.expectRevert(abi.encodeWithSelector(RayFiToken.RayFi__VaultDoesNotExist.selector, address(rayFiToken)));
        rayFiToken.stake(address(rayFiToken), TRANSFER_AMOUNT);
    }

    function testCannotRemoveInexistentVaults() public {
        vm.expectRevert(abi.encodeWithSelector(RayFiToken.RayFi__VaultDoesNotExist.selector, address(0)));
        vm.prank(msg.sender);
        rayFiToken.removeVault(address(0));
    }

    ////////////////////
    // Reward Tests ////
    ////////////////////

    function testStatelessDistributionWorksForMultipleUsers() public minimumBalanceForRewardsSet fundUserBase {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);

        rayFiToken.distributeRewardsStateless(0, new address[](0));
        vm.stopPrank();

        for (uint256 i; i < USER_COUNT; ++i) {
            assert(rewardToken.balanceOf(users[i]) >= TRANSFER_AMOUNT / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS);
        }
        assert(rewardToken.balanceOf(msg.sender) >= TRANSFER_AMOUNT / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS);
    }

    function testStatelessDistributionEmitsEvents() public {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);

        vm.recordLogs();
        rayFiToken.distributeRewardsStateless(0, new address[](0));
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[1].topics[0], keccak256("RewardsDistributed(uint256,uint256)"));
        assert(entries[1].topics[1] >= bytes32(TRANSFER_AMOUNT - ACCEPTED_PRECISION_LOSS));
        assertEq(entries[1].topics[2], 0);
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
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);
        rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(msg.sender));

        uint256[USER_COUNT] memory stakedBalancesBefore;
        for (uint256 i; i < USER_COUNT; ++i) {
            stakedBalancesBefore[i] = rayFiToken.getStakedBalanceOf(users[i]);
        }
        uint256 stakedBalanceBeforeOwner = rayFiToken.getStakedBalanceOf(msg.sender);

        rayFiToken.distributeRewardsStateless(0, new address[](0));
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_DIVIDEND_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rayFiToken.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
            );
        }
        assert(
            rayFiToken.getStakedBalanceOf(msg.sender)
                >= stakedBalanceBeforeOwner + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
        );
    }

    function testStatelessReinvestmentEmitsEvents() public liquidityAdded {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);
        rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(msg.sender));

        vm.recordLogs();
        rayFiToken.distributeRewardsStateless(0, new address[](0));
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_DIVIDEND_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        assertEq(entries[6].topics[0], keccak256("RewardsDistributed(uint256,uint256)"));
        assertEq(entries[6].topics[1], 0);
        assert(entries[6].topics[2] >= bytes32(amountOut - ACCEPTED_PRECISION_LOSS));
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
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);
        rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(msg.sender));

        uint256[USER_COUNT] memory stakedBalancesBefore;
        for (uint256 i; i < USER_COUNT; ++i) {
            stakedBalancesBefore[i] = rayFiToken.getStakedBalanceOf(users[i]);
        }
        uint256 stakedBalanceBeforeOwner = rayFiToken.getStakedBalanceOf(msg.sender);

        rayFiToken.distributeRewardsStateless(0, new address[](0));
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_DIVIDEND_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rayFiToken.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / ((USER_COUNT + 1) * 2) - ACCEPTED_PRECISION_LOSS
            );
        }
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rewardToken.balanceOf(users[i]) >= TRANSFER_AMOUNT / ((USER_COUNT + 1) * 2) - ACCEPTED_PRECISION_LOSS
            );
        }
        assert(
            rayFiToken.getStakedBalanceOf(msg.sender)
                >= stakedBalanceBeforeOwner + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
        );
    }

    function testStatefulDistributionWorksForMultipleUsers() public minimumBalanceForRewardsSet fundUserBase {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);

        // We arbitrarily run an excessive amount of distributions to ensure nothing breaks
        for (uint256 i; i < USER_COUNT; ++i) {
            rayFiToken.distributeRewardsStateful{gas: GAS_FOR_DIVIDENDS * 2}(GAS_FOR_DIVIDENDS, 0, new address[](0));
        }
        vm.stopPrank();

        for (uint256 i; i < USER_COUNT; ++i) {
            assert(rewardToken.balanceOf(users[i]) >= TRANSFER_AMOUNT / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS);
        }
    }

    function testStatefulDistributionEmitsEvents() public {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);

        vm.recordLogs();
        rayFiToken.distributeRewardsStateful{gas: GAS_FOR_DIVIDENDS * 2}(GAS_FOR_DIVIDENDS, 0, new address[](0));
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[1].topics[0], keccak256("RewardsDistributed(uint256,uint256)"));
        assert(entries[1].topics[1] >= bytes32(TRANSFER_AMOUNT - ACCEPTED_PRECISION_LOSS));
        assertEq(entries[1].topics[2], 0);
    }

    function testStatefulReinvestmentWorksForMultipleUsers()
        public
        liquidityAdded
        minimumBalanceForRewardsSet
        fundUserBase
        fullyStakeUserBase
    {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);
        rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(msg.sender));

        uint256[USER_COUNT] memory stakedBalancesBefore;
        for (uint256 i; i < USER_COUNT; ++i) {
            stakedBalancesBefore[i] = rayFiToken.getStakedBalanceOf(users[i]);
        }
        uint256 stakedBalanceBeforeOwner = rayFiToken.getStakedBalanceOf(msg.sender);

        // We arbitrarily run an excessive amount of distributions to ensure nothing breaks
        for (uint256 i; i < USER_COUNT; ++i) {
            try rayFiToken.distributeRewardsStateful{gas: GAS_FOR_DIVIDENDS * 10}(
                GAS_FOR_DIVIDENDS, 0, new address[](0)
            ) {
                continue;
            } catch (bytes memory reason) {
                bytes4 desiredSelector = bytes4(keccak256(bytes("RayFi__NothingToDistribute()")));
                bytes4 receivedSelector = bytes4(reason);
                assertEq(desiredSelector, receivedSelector);
                break;
            }
        }
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_DIVIDEND_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rayFiToken.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
            );
        }
        assert(
            rayFiToken.getStakedBalanceOf(msg.sender)
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
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);
        rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(msg.sender));

        uint256[USER_COUNT] memory stakedBalancesBefore;
        for (uint256 i; i < USER_COUNT; ++i) {
            stakedBalancesBefore[i] = rayFiToken.getStakedBalanceOf(users[i]);
        }
        uint256 stakedBalanceBeforeOwner = rayFiToken.getStakedBalanceOf(msg.sender);

        vm.startPrank(msg.sender);
        for (uint256 i; i < USER_COUNT; ++i) {
            if (
                rayFiToken.distributeRewardsStateful{gas: GAS_FOR_DIVIDENDS * 10}(
                    GAS_FOR_DIVIDENDS, 0, new address[](0)
                )
            ) {
                break;
            }
        }
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_DIVIDEND_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rayFiToken.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / ((USER_COUNT + 1) * 2) - ACCEPTED_PRECISION_LOSS
            );
        }
        for (uint256 i; i < USER_COUNT; ++i) {
            assert(
                rewardToken.balanceOf(users[i]) >= TRANSFER_AMOUNT / ((USER_COUNT + 1) * 2) - ACCEPTED_PRECISION_LOSS
            );
        }
        assert(
            rayFiToken.getStakedBalanceOf(msg.sender)
                >= stakedBalanceBeforeOwner + amountOut / (USER_COUNT + 1) - ACCEPTED_PRECISION_LOSS
        );
    }

    function testStatelessDistributionRevertsIfStatefulDistributionIsInProgress() public fundUserBase {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);

        rayFiToken.distributeRewardsStateful{gas: GAS_FOR_DIVIDENDS * 2}(GAS_FOR_DIVIDENDS, 0, new address[](0));

        vm.expectRevert(RayFiToken.RayFi__DistributionInProgress.selector);
        rayFiToken.distributeRewardsStateless(0, new address[](0));
        vm.stopPrank();
    }

    function testDistributionToSpecificVaultWorks() public liquidityAdded minimumBalanceForRewardsSet {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);
        rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(msg.sender));

        address[] memory vaults = new address[](1);
        vaults[0] = address(rayFiToken);
        rayFiToken.distributeRewardsStateless(0, vaults);
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_DIVIDEND_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        assert(rayFiToken.getStakedBalanceOf(msg.sender) >= TRANSFER_AMOUNT + amountOut - ACCEPTED_PRECISION_LOSS);
    }

    function testReinvetmentWithNonZeroSlippageWorks() public liquidityAdded minimumBalanceForRewardsSet {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);
        rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(msg.sender));

        rayFiToken.distributeRewardsStateless(5, new address[](0));
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_DIVIDEND_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        assert(rayFiToken.getStakedBalanceOf(msg.sender) >= TRANSFER_AMOUNT + amountOut - ACCEPTED_PRECISION_LOSS);
    }

    function testDistributionRevertsOnZeroRewardBalance() public {
        vm.startPrank(msg.sender);
        vm.expectRevert(RayFiToken.RayFi__NothingToDistribute.selector);
        rayFiToken.distributeRewardsStateless(0, new address[](0));
    }

    function testOnlyOwnerCanStartDistribution() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.distributeRewardsStateless(0, new address[](0));
    }

    function testStatefulDistributionRevertsOnInsufficientGas() public {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);

        vm.expectRevert();
        rayFiToken.distributeRewardsStateful{gas: GAS_FOR_DIVIDENDS / 2}(GAS_FOR_DIVIDENDS, 0, new address[](0));

        rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(msg.sender));
        
        vm.expectRevert();
        rayFiToken.distributeRewardsStateful{gas: GAS_FOR_DIVIDENDS / 2}(GAS_FOR_DIVIDENDS, 0, new address[](0));
        vm.stopPrank();
    }

    function testEmptyVaultsDoNotBreakDistribution() public liquidityAdded {
        rewardToken.mint(msg.sender, TRANSFER_AMOUNT);
        vm.startPrank(msg.sender);
        rewardToken.transfer(address(rayFiToken), TRANSFER_AMOUNT);
        rayFiToken.stake(address(rayFiToken), rayFiToken.balanceOf(msg.sender));

        address[] memory vaults = new address[](2);
        vaults[0] = address(0);
        vaults[1] = address(rayFiToken);
        rayFiToken.distributeRewardsStateless(0, vaults);
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(TRANSFER_AMOUNT, INITIAL_DIVIDEND_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        assert(rayFiToken.getStakedBalanceOf(msg.sender) >= TRANSFER_AMOUNT + amountOut - ACCEPTED_PRECISION_LOSS);
    }

    ////////////////////
    // Setter Tests ////
    ////////////////////

    function testSetFeeAmounts() public {
        // Set valid fee amounts
        vm.startPrank(msg.sender);
        vm.recordLogs();
        rayFiToken.setFeeAmounts(BUY_FEE, SELL_FEE);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("FeeAmountsUpdated(uint8,uint8)"));
        (uint8 buyFee, uint8 sellFee) = abi.decode(entries[0].data, (uint8, uint8));
        assertEq(buyFee, BUY_FEE);
        assertEq(sellFee, SELL_FEE);
        assertEq(rayFiToken.getBuyFee(), BUY_FEE);
        assertEq(rayFiToken.getSellFee(), SELL_FEE);

        // Revert when total fee exceeds maximum
        buyFee = 99;
        sellFee = 99;
        vm.expectRevert(abi.encodeWithSelector(RayFiToken.RayFi__FeesTooHigh.selector, buyFee + sellFee));
        rayFiToken.setFeeAmounts(buyFee, sellFee);
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setFeeAmounts(BUY_FEE, SELL_FEE);
    }

    function testSetMinimumTokenBalanceForRewards() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        rayFiToken.setMinimumTokenBalanceForRewards(MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("MinimumTokenBalanceForRewardsUpdated(uint256,uint256)"));
        assertEq(entries[0].topics[1], bytes32(MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS));
        assertEq(entries[0].topics[2], bytes32(0));
        assertEq(rayFiToken.getMinimumTokenBalanceForRewards(), MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS);
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setMinimumTokenBalanceForRewards(MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS);
    }

    function testSetIsExcludedFromRewards() public {
        vm.prank(msg.sender);
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);
        rayFiToken.stake(address(rayFiToken), TRANSFER_AMOUNT);

        // Test valid call
        vm.recordLogs();
        vm.startPrank(msg.sender);
        rayFiToken.setIsExcludedFromRewards(address(this), true);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[2].topics[0], keccak256("IsUserExcludedFromRewardsUpdated(address,bool)"));
        assertEq(entries[2].topics[1], bytes32(uint256(uint160(address(this)))));
        assertEq(entries[2].topics[2], bytes32(uint256(1)));
        assertEq(rayFiToken.getShareholders().length, 1);
        assertEq(rayFiToken.balanceOf(address(this)), TRANSFER_AMOUNT);

        rayFiToken.setIsExcludedFromRewards(address(this), false);
        vm.stopPrank();

        assertEq(rayFiToken.getShareholders().length, 2);

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setIsExcludedFromRewards(address(this), false);
    }

    function testSetRewardToken() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newRewardToken = address(DUMMY_ADDRESS);
        rayFiToken.setRewardToken(newRewardToken);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("RewardTokenUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newRewardToken))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(address(rewardToken)))));
        assertEq(rayFiToken.getRewardToken(), newRewardToken);

        // Revert when zero address is passed as input
        vm.expectRevert(RayFiToken.RayFi__CannotSetToZeroAddress.selector);
        rayFiToken.setRewardToken(address(0));
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setRewardToken(newRewardToken);
    }

    function testSetRouter() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newRouter = address(DUMMY_ADDRESS);
        rayFiToken.setRouter(newRouter);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("RouterUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newRouter))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(address(router)))));

        // Revert when zero address is passed as input
        vm.expectRevert(RayFiToken.RayFi__CannotSetToZeroAddress.selector);
        rayFiToken.setRouter(address(0));
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setRouter(newRouter);
    }

    function testSetFeeReceiver() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newFeeReceiver = address(DUMMY_ADDRESS);
        rayFiToken.setFeeReceiver(newFeeReceiver);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("FeeReceiverUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newFeeReceiver))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(FEE_RECEIVER))));
        assertEq(rayFiToken.getFeeReceiver(), newFeeReceiver);

        // Revert when zero address is passed as input
        vm.expectRevert(RayFiToken.RayFi__CannotSetToZeroAddress.selector);
        rayFiToken.setFeeReceiver(address(0));
        vm.stopPrank();

        // Revert when called by non-msg.sender
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setFeeReceiver(newFeeReceiver);
    }

    function testSetSwapReceiver() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newSwapReceiver = address(DUMMY_ADDRESS);
        rayFiToken.setSwapReceiver(newSwapReceiver);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("SwapReceiverUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newSwapReceiver))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(DIVIDEND_RECEIVER))));

        // Revert when zero address is passed as input
        vm.expectRevert(RayFiToken.RayFi__CannotSetToZeroAddress.selector);
        rayFiToken.setSwapReceiver(address(0));
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setSwapReceiver(newSwapReceiver);
    }
}
