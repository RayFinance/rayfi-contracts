// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RayFi} from "../../src/RayFi.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {DeployRayFi} from "../../script/DeployRayFi.s.sol";
import {DeployMockVaults} from "../../script/DeployMockVaults.s.sol";
import {
    FundRayFi,
    CreateRayFiLiquidityPool,
    CreateRayFiUsers,
    FullyStakeRayFiUsersSingleVault,
    PartiallyStakeRayFiUsersSingleVault,
    AddMockRayFiVaults,
    FullyStakeRayFiUsersMultipleVaults,
    PartiallyStakeRayFiUsersMultipleVaults
} from "../../script/Interactions.s.sol";

contract InteractionsTest is Test {
    RayFi rayFi;
    ERC20Mock rewardToken;
    IUniswapV2Router02 router;
    ERC20Mock btcb;
    ERC20Mock eth;
    ERC20Mock bnb;

    uint256 constant FUND_AMOUNT = 10_000 ether;
    uint256 constant INITIAL_RAYFI_LIQUIDITY = 2_858_550 ether;
    uint256 constant INITIAL_REWARD_LIQUIDITY = 14_739 ether;
    uint256 constant USDT_LIQUIDITY = 1_000_000 ether;
    uint256 constant BTCB_LIQUIDITY = 100 ether;
    uint256 constant ETH_LIQUIDITY = 1_000 ether;
    uint256 constant BNB_LIQUIDITY = 10_000 ether;
    uint256 constant USER_COUNT = 100;
    uint256 constant MAX_ATTEMPTS = 100;
    uint32 public constant GAS_FOR_REWARDS = 1_000_000;
    uint8 constant ACCEPTED_PRECISION_LOSS = 100;

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address SWAP_RECEIVER = makeAddr("rewardReceiver");

    function setUp() public {
        DeployRayFi deployRayFi = new DeployRayFi();
        (rayFi, rewardToken, router) = deployRayFi.run(FEE_RECEIVER, SWAP_RECEIVER);

        DeployMockVaults deployMockVaults = new DeployMockVaults();
        (address btcbAddress, address ethAddress, address bnbAddress) = deployMockVaults.run();
        btcb = ERC20Mock(btcbAddress);
        eth = ERC20Mock(ethAddress);
        bnb = ERC20Mock(bnbAddress);
    }

    function testFundRayFi() public {
        FundRayFi fundRayFi = new FundRayFi();
        fundRayFi.fundRayFi(address(rayFi));

        assertEq(rewardToken.balanceOf(address(rayFi)), FUND_AMOUNT);
    }

    function testCreateRayFiLiquidityPool() public {
        CreateRayFiLiquidityPool createRayFiLiquidityPool = new CreateRayFiLiquidityPool();
        vm.startPrank(msg.sender);
        createRayFiLiquidityPool.createRayFiLiquidityPool(address(rayFi), address(rewardToken), address(router));
        vm.stopPrank();

        assert(IUniswapV2Factory(router.factory()).getPair(address(rayFi), address(rewardToken)) != address(0));
    }

    function testCreateRayFiUsers() public {
        CreateRayFiUsers createRayFiUsers = new CreateRayFiUsers();
        vm.startPrank(msg.sender);
        createRayFiUsers.createRayFiUsers(address(rayFi));
        vm.stopPrank();

        assertEq(rayFi.getShareholders().length, createRayFiUsers.USER_COUNT() + 1);
    }

    function testFullyStakeRayFiUsersSingleVault() public {
        CreateRayFiUsers createRayFiUsers = new CreateRayFiUsers();
        vm.startPrank(msg.sender);
        createRayFiUsers.createRayFiUsers(address(rayFi));
        vm.stopPrank();

        FullyStakeRayFiUsersSingleVault fullyStakeRayFiUsersSingleVault = new FullyStakeRayFiUsersSingleVault();
        fullyStakeRayFiUsersSingleVault.fullyStakeRayFiUsers(address(rayFi));

        assertEq(rayFi.getTotalRewardShares(), rayFi.getTotalStakedAmount());
    }

    function testPartiallyStakeRayFiUsersSingleVault() public {
        CreateRayFiUsers createRayFiUsers = new CreateRayFiUsers();
        vm.startPrank(msg.sender);
        createRayFiUsers.createRayFiUsers(address(rayFi));
        vm.stopPrank();

        PartiallyStakeRayFiUsersSingleVault partiallyStakeRayFiUsersSingleVault =
            new PartiallyStakeRayFiUsersSingleVault();
        partiallyStakeRayFiUsersSingleVault.partiallyStakeRayFiUsers(address(rayFi));

        assertEq(rayFi.getTotalRewardShares() / 2, rayFi.getTotalStakedAmount());
    }

    function testAddMockRayFiVaults() public {
        AddMockRayFiVaults addMockRayFiVaults = new AddMockRayFiVaults();
        vm.startPrank(msg.sender);
        addMockRayFiVaults.addMockRayFiVaults(
            address(rayFi), address(rewardToken), address(btcb), address(eth), address(bnb), address(router)
        );

        address[4] memory vaults = [address(rayFi), address(btcb), address(eth), address(bnb)];
        vm.startPrank(msg.sender);
        for (uint256 i; i < vaults.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(RayFi.RayFi__VaultAlreadyExists.selector, vaults[i]));
            rayFi.addVault(vaults[i]);
        }
        vm.stopPrank();
    }

    function testDistributionNoVaults() public {
        FundRayFi fundRayFi = new FundRayFi();
        fundRayFi.fundRayFi(address(rayFi));

        CreateRayFiUsers createRayFiUsers = new CreateRayFiUsers();
        vm.startPrank(msg.sender);
        createRayFiUsers.createRayFiUsers(address(rayFi));

        vm.startPrank(msg.sender);
        rayFi.distributeRewardsStateless(0, new address[](0));
        vm.stopPrank();

        address[] memory users = rayFi.getShareholders();
        for (uint256 i; i < users.length; ++i) {
            assert(rewardToken.balanceOf(users[i]) >= FUND_AMOUNT / (users.length) - ACCEPTED_PRECISION_LOSS);
        }
    }

    function testDistributionOnlySingleVault() public {
        FundRayFi fundRayFi = new FundRayFi();
        fundRayFi.fundRayFi(address(rayFi));

        CreateRayFiLiquidityPool createRayFiLiquidityPool = new CreateRayFiLiquidityPool();
        vm.startPrank(msg.sender);
        createRayFiLiquidityPool.createRayFiLiquidityPool(address(rayFi), address(rewardToken), address(router));

        CreateRayFiUsers createRayFiUsers = new CreateRayFiUsers();
        vm.startPrank(msg.sender);
        createRayFiUsers.createRayFiUsers(address(rayFi));

        FullyStakeRayFiUsersSingleVault fullyStakeRayFiUsersSingleVault = new FullyStakeRayFiUsersSingleVault();
        fullyStakeRayFiUsersSingleVault.fullyStakeRayFiUsers(address(rayFi));

        address[] memory users = rayFi.getShareholders();
        uint256[] memory stakedBalancesBefore = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }

        vm.startPrank(msg.sender);
        rayFi.distributeRewardsStateless(0, new address[](0));
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(FUND_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < users.length; ++i) {
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / users.length - ACCEPTED_PRECISION_LOSS
            );
        }
    }

    function testMixedDistributionSingleVault() public {
        FundRayFi fundRayFi = new FundRayFi();
        fundRayFi.fundRayFi(address(rayFi));

        CreateRayFiLiquidityPool createRayFiLiquidityPool = new CreateRayFiLiquidityPool();
        vm.startPrank(msg.sender);
        createRayFiLiquidityPool.createRayFiLiquidityPool(address(rayFi), address(rewardToken), address(router));

        CreateRayFiUsers createRayFiUsers = new CreateRayFiUsers();
        vm.startPrank(msg.sender);
        createRayFiUsers.createRayFiUsers(address(rayFi));

        PartiallyStakeRayFiUsersSingleVault partiallyStakeRayFiUsersSingleVault =
            new PartiallyStakeRayFiUsersSingleVault();
        partiallyStakeRayFiUsersSingleVault.partiallyStakeRayFiUsers(address(rayFi));

        address[] memory users = rayFi.getShareholders();
        uint256[] memory stakedBalancesBefore = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }

        vm.startPrank(msg.sender);
        rayFi.distributeRewardsStateless(0, new address[](0));
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(FUND_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < users.length; ++i) {
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / (users.length * 2) - ACCEPTED_PRECISION_LOSS
            );
        }
        for (uint256 i; i < users.length; ++i) {
            assert(rewardToken.balanceOf(users[i]) >= FUND_AMOUNT / (users.length * 2) - ACCEPTED_PRECISION_LOSS);
        }
    }
        }
    }
