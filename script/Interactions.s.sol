// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {RayFi} from "../src/RayFi.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract FundRayFi is Script {
    uint256 constant FUND_AMOUNT = 10_000 ether;

    function fundRayFi(address rayFiAddress) public {
        RayFi rayFi = RayFi(rayFiAddress);
        ERC20Mock rewardToken = ERC20Mock(rayFi.getRewardToken());
        rewardToken.mint(rayFiAddress, FUND_AMOUNT);
    }

    function run() external {
        address mostRecentDeployed = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);
        vm.startBroadcast();
        fundRayFi(mostRecentDeployed);
        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}

contract CreateRayFiLiquidityPool is Script {
    uint256 constant INITIAL_RAYFI_LIQUIDITY = 2_858_550 ether;
    uint256 constant INITIAL_REWARD_LIQUIDITY = 14_739 ether;

    modifier prankOwner(address rayFiAddress) {
        bool isOwner = RayFi(rayFiAddress).owner() == msg.sender;
        if (!isOwner) {
            vm.startPrank(tx.origin);
        }
        _;
        if (!isOwner) {
            vm.stopPrank();
        }
    }

    function createRayFiLiquidityPool(address rayFiAddress, address rewardToken, address router)
        public
        prankOwner(rayFiAddress)
    {
        RayFi rayFi = RayFi(rayFiAddress);
        ERC20Mock(rewardToken).mint(address(this), INITIAL_REWARD_LIQUIDITY);

        rayFi.approve(router, INITIAL_RAYFI_LIQUIDITY);
        ERC20Mock(rewardToken).approve(router, INITIAL_REWARD_LIQUIDITY);

        IUniswapV2Router02(router).addLiquidity(
            rayFiAddress,
            rewardToken,
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_REWARD_LIQUIDITY,
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_REWARD_LIQUIDITY,
            msg.sender,
            block.timestamp + 1000
        );

        address pair = IUniswapV2Factory(IUniswapV2Router02(router).factory()).getPair(rayFiAddress, rewardToken);
        rayFi.setIsAutomatedMarketPair(pair, true);
        rayFi.setIsExcludedFromRewards(pair, true);
    }

    function run() external {
        address mostRecentDeployedRayFi = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);

        address mostRecentDeployedRewardToken;
        address mostRecentDeployedRouter;
        if (block.chainid == 5611) {
            HelperConfig helperConfig = new HelperConfig();
            (,, mostRecentDeployedRewardToken, mostRecentDeployedRouter,,,) = helperConfig.activeNetworkConfig();
        } else {
            mostRecentDeployedRewardToken = DevOpsTools.get_most_recent_deployment("MockUSDT", block.chainid);
        mostRecentDeployedRouter = DevOpsTools.get_most_recent_deployment("UniswapV2Router02", block.chainid);
        }

        vm.startBroadcast();
        createRayFiLiquidityPool(mostRecentDeployedRayFi, mostRecentDeployedRewardToken, mostRecentDeployedRouter);
        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}

contract CreateRayFiUsers is Script {
    uint256 public constant USER_COUNT = 100;

    function createRayFiUsers(address rayFiAddress) public {
        RayFi rayFi = RayFi(rayFiAddress);
        vm.startPrank(msg.sender);
        address[100] memory users;
        uint256 balance = rayFi.balanceOf(msg.sender);
        for (uint256 i = 0; i < USER_COUNT; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked(i + 1)))));
            rayFi.transfer(users[i], balance / (USER_COUNT + 1));
        }
    }

    function run() external {
        address mostRecentDeployed = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);
        vm.startBroadcast();
        createRayFiUsers(mostRecentDeployed);
        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}

contract FullyStakeRayFiUsersSingleVault is Script {
    function fullyStakeRayFiUsers(address rayFiAddress) public {
        RayFi rayFi = RayFi(rayFiAddress);
        address[] memory users = rayFi.getShareholders();
        for (uint256 i; i < users.length; i++) {
            vm.startPrank(users[i]);
            rayFi.stake(rayFiAddress, rayFi.balanceOf(users[i]));
            vm.stopPrank();
        }
    }

    function run() external {
        address mostRecentDeployed = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);
        vm.startBroadcast();
        fullyStakeRayFiUsers(mostRecentDeployed);
        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}

contract PartiallyStakeRayFiUsersSingleVault is Script {
    function partiallyStakeRayFiUsers(address rayFiAddress) public {
        RayFi rayFi = RayFi(rayFiAddress);
        address[] memory users = rayFi.getShareholders();
        for (uint256 i; i < users.length; i++) {
            vm.startPrank(users[i]);
            rayFi.stake(rayFiAddress, rayFi.balanceOf(users[i]) / 2);
            vm.stopPrank();
        }
    }

    function run() external {
        address mostRecentDeployed = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);
        vm.startBroadcast();
        partiallyStakeRayFiUsers(mostRecentDeployed);
        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}

contract AddMockRayFiVaults is Script {
        uint256 constant USDT_LIQUIDITY = 1_000_000 ether;
    uint256 constant BTCB_LIQUIDITY = 100 ether;
    uint256 constant ETH_LIQUIDITY = 1_000 ether;
    uint256 constant BNB_LIQUIDITY = 10_000 ether;

    modifier prankOwner(address rayFiAddress) {
        bool isOwner = RayFi(rayFiAddress).owner() == msg.sender;
        if (!isOwner) {
            vm.startPrank(tx.origin);
        }
        _;
        if (!isOwner) {
            vm.stopPrank();
        }
    }

    function addMockRayFiVaults(
        address rayFiAddress,
        address mockUSDT,
        address mockBTCB,
        address mockETH,
        address mockBNB,
        address routerAddress
    ) public prankOwner(rayFiAddress) {
        RayFi rayFi = RayFi(rayFiAddress);
                rayFi.addVault(mockBTCB);
        rayFi.addVault(mockETH);
        rayFi.addVault(mockBNB);

        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);
        address[3] memory vaultTokens = [mockBTCB, mockETH, mockBNB];
        uint256[3] memory vaultLiquidity = [BTCB_LIQUIDITY, ETH_LIQUIDITY, BNB_LIQUIDITY];
        for (uint256 i; i < 3; i++) {
            ERC20Mock(vaultTokens[i]).mint(msg.sender, vaultLiquidity[i]);

            ERC20Mock(vaultTokens[i]).approve(routerAddress, vaultLiquidity[i]);
            ERC20Mock(mockUSDT).approve(routerAddress, USDT_LIQUIDITY);

            router.addLiquidity(
                mockUSDT,
                vaultTokens[i],
                USDT_LIQUIDITY,
                vaultLiquidity[i],
                USDT_LIQUIDITY,
                vaultLiquidity[i],
                msg.sender,
                block.timestamp + 1000
            );
        }
            }

    function run() external {
        address mostRecentDeployedRayFi = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);
        address mostRecentDeployedMockUSDT = DevOpsTools.get_most_recent_deployment("MockUSDT", block.chainid);
        address mostRecentDeployedMockBTCB = DevOpsTools.get_most_recent_deployment("MockBTCB", block.chainid);
        address mostRecentDeployedMockETH = DevOpsTools.get_most_recent_deployment("MockETH", block.chainid);
        address mostRecentDeployedMockBNB = DevOpsTools.get_most_recent_deployment("MockBNB", block.chainid);

        address mostRecentDeployedRouter;
        if (block.chainid == 5611) {
            HelperConfig helperConfig = new HelperConfig();
            (,,, mostRecentDeployedRouter,,,) = helperConfig.activeNetworkConfig();
        } else {
            mostRecentDeployedRouter = DevOpsTools.get_most_recent_deployment("UniswapV2Router02", block.chainid);
        }

        vm.startBroadcast();
        addMockRayFiVaults(
            mostRecentDeployedRayFi,
            mostRecentDeployedMockUSDT,
            mostRecentDeployedMockBTCB,
            mostRecentDeployedMockETH,
            mostRecentDeployedMockBNB,
            mostRecentDeployedRouter
        );

        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}

contract FullyStakeRayFiUsersMultipleVaults is Script {
    function fullyStakeRayFiUsersMultipleVaults(address rayFiAddress, address[3] memory vaultTokens) public {
        RayFi rayFi = RayFi(rayFiAddress);
        address[] memory users = rayFi.getShareholders();
        for (uint256 i; i < users.length; i++) {
            vm.startPrank(users[i]);
            uint256 balance = rayFi.balanceOf(users[i]);
            rayFi.stake(vaultTokens[0], balance / 4);
            rayFi.stake(vaultTokens[1], balance / 4);
            rayFi.stake(vaultTokens[2], balance / 4);
            rayFi.stake(rayFiAddress, rayFi.balanceOf(users[i]));
            vm.stopPrank();
        }
    }

    function run() external {
        address mostRecentDeployedRayFi = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);
        address mostRecentDeployedMockBTCB = DevOpsTools.get_most_recent_deployment("MockBTCB", block.chainid);
        address mostRecentDeployedMockETH = DevOpsTools.get_most_recent_deployment("MockETH", block.chainid);
        address mostRecentDeployedMockBNB = DevOpsTools.get_most_recent_deployment("MockBNB", block.chainid);
        vm.startBroadcast();
        address[3] memory vaultTokens =
            [mostRecentDeployedMockBTCB, mostRecentDeployedMockETH, mostRecentDeployedMockBNB];
        fullyStakeRayFiUsersMultipleVaults(mostRecentDeployedRayFi, vaultTokens);
        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}

contract PartiallyStakeRayFiUsersMultipleVaults is Script {
    function partiallyStakeRayFiUsersMultipleVaults(address rayFiAddress, address[3] memory vaultTokens) public {
        RayFi rayFi = RayFi(rayFiAddress);
        address[] memory users = rayFi.getShareholders();
        for (uint256 i; i < users.length; i++) {
            vm.startPrank(users[i]);
            uint256 balance = rayFi.balanceOf(users[i]);
            rayFi.stake(vaultTokens[0], balance / 8);
            rayFi.stake(vaultTokens[1], balance / 8);
            rayFi.stake(vaultTokens[2], balance / 8);
            rayFi.stake(rayFiAddress, balance / 8);
            vm.stopPrank();
        }
    }

    function run() external {
        address mostRecentDeployedRayFi = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);
        address mostRecentDeployedMockBTCB = DevOpsTools.get_most_recent_deployment("MockBTCB", block.chainid);
        address mostRecentDeployedMockETH = DevOpsTools.get_most_recent_deployment("MockETH", block.chainid);
        address mostRecentDeployedMockBNB = DevOpsTools.get_most_recent_deployment("MockBNB", block.chainid);
        vm.startBroadcast();
        address[3] memory vaultTokens =
            [mostRecentDeployedMockBTCB, mostRecentDeployedMockETH, mostRecentDeployedMockBNB];
        partiallyStakeRayFiUsersMultipleVaults(mostRecentDeployedRayFi, vaultTokens);
        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}

contract DistributeRewardsStateless is Script {

    modifier prankOwner(address rayFiAddress) {
        bool isOwner = RayFi(rayFiAddress).owner() == msg.sender;
        if (!isOwner) {
            vm.startPrank(tx.origin);
        }
        _;
        if (!isOwner) {
            vm.stopPrank();
        }
    }

    function distributeRewardsStateless(address rayFiAddress) public prankOwner(rayFiAddress) {
        RayFi rayFi = RayFi(rayFiAddress);
        rayFi.snapshot();
        rayFi.distributeRewardsStateless(0);
    }

    function run() external {
        address mostRecentDeployed = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);
        vm.startBroadcast();
        distributeRewardsStateless(mostRecentDeployed);
        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}

contract DistributeRewardsStateful is Script {
    uint256 constant MAX_ITERATIONS = 10;
    uint32 constant GAS_FOR_REWARDS = 10_000_000;

    modifier prankOwner(address rayFiAddress) {
        bool isOwner = RayFi(rayFiAddress).owner() == msg.sender;
        if (!isOwner) {
            vm.startPrank(tx.origin);
        }
        _;
        if (!isOwner) {
            vm.stopPrank();
        }
    }

    function distributeRewardsStateful(address rayFiAddress) public prankOwner(rayFiAddress) {
        RayFi rayFi = RayFi(rayFiAddress);
        rayFi.snapshot();
        for (uint256 i; i < MAX_ITERATIONS; i++) {
            if (rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS}(GAS_FOR_REWARDS / 2, 0, new address[](0))) {
                break;
            }
        }
    }

    function run() external {
        address mostRecentDeployed = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);
        vm.startBroadcast();
        distributeRewardsStateful(mostRecentDeployed);
        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}
