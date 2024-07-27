// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {RayFi} from "../src/RayFi.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract DeployRayFi is Script {
    function run()
        external
        returns (RayFi rayFi, ERC20Mock rewardToken, IUniswapV2Router02 router, HelperConfig helperConfig)
    {
        helperConfig = new HelperConfig();
        (address feeReceiver, address swapReceiver, address rewardTokenAddress, address routerAddress,,,) =
            helperConfig.activeNetworkConfig();

        vm.startBroadcast();
        rayFi = new RayFi(routerAddress, rewardTokenAddress, swapReceiver, feeReceiver);
        vm.stopBroadcast();
        return (rayFi, ERC20Mock(rewardTokenAddress), IUniswapV2Router02(routerAddress), helperConfig);
    }

    // Excludes contract from coverage report
    function test() public {}
}
