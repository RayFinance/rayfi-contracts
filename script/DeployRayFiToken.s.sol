// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {RayFiToken} from "../src/RayFiToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract DeployRayFiToken is Script {
    function run(address feeReceiver, address dividendReceiver)
        external
        returns (RayFiToken rayFiToken, ERC20Mock dividendToken, IUniswapV2Router02 router)
    {
        HelperConfig helper = new HelperConfig();
        (address dividendTokenAddress, address routerAddress) = helper.activeNetworkConfig();

        vm.startBroadcast();
        rayFiToken = new RayFiToken(dividendTokenAddress, routerAddress, feeReceiver, dividendReceiver);
        vm.stopBroadcast();
        return (rayFiToken, ERC20Mock(dividendTokenAddress), IUniswapV2Router02(routerAddress));
    }

    // Excludes contract from coverage report
    function test() public {}
}
