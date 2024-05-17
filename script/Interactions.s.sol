// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {RayFi} from "../src/RayFi.sol";
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

    function createRayFiLiquidityPool(address rayFi, address rewardToken, address router) public {
        vm.startPrank(msg.sender);
        ERC20Mock(rewardToken).mint(msg.sender, INITIAL_REWARD_LIQUIDITY);

        RayFi(rayFi).approve(router, INITIAL_RAYFI_LIQUIDITY);
        ERC20Mock(rewardToken).approve(router, INITIAL_REWARD_LIQUIDITY);

        IUniswapV2Router02(router).addLiquidity(
            rayFi,
            rewardToken,
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_REWARD_LIQUIDITY,
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_REWARD_LIQUIDITY,
            address(this),
            block.timestamp
        );

        address pair = IUniswapV2Factory(IUniswapV2Router02(router).factory()).getPair(rayFi, rewardToken);
        RayFi(rayFi).setAutomatedMarketPair(pair, true);
        RayFi(rayFi).setIsExcludedFromRewards(pair, true);
        vm.stopPrank();
    }

    function run() external {
        address mostRecentDeployedRayFi = DevOpsTools.get_most_recent_deployment("RayFi", block.chainid);
        address mostRecentDeployedRewardToken = DevOpsTools.get_most_recent_deployment("MockUSDT", block.chainid);
        address mostRecentDeployedRouter = DevOpsTools.get_most_recent_deployment("UniswapV2Router02", block.chainid);
        vm.startBroadcast();
        createRayFiLiquidityPool(mostRecentDeployedRayFi, mostRecentDeployedRewardToken, mostRecentDeployedRouter);
        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}
