// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {RayFiToken, ERC20} from "../src/RayFiToken.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract DeployRayFiToken is Script {
    uint256 public constant INITIAL_RAYFI_LIQUIDITY = 2_858_550 * (10 ** 18);
    uint256 public constant INITIAL_DIVIDEND_LIQUIDITY = 14_739 * (10 ** 18);

    function run(address feeReceiver, address dividendReceiver)
        external
        returns (RayFiToken rayFiToken, ERC20 dividendToken, IUniswapV2Router02 router)
    {
        HelperConfig helper = new HelperConfig();
        (address dividendTokenAddress, address routerAddress) = helper.activeNetworkConfig();

        vm.startBroadcast();
        rayFiToken = new RayFiToken(dividendTokenAddress, routerAddress, feeReceiver, dividendReceiver);
        vm.stopBroadcast();
        return (rayFiToken, ERC20(dividendTokenAddress), IUniswapV2Router02(routerAddress));
    }
}
