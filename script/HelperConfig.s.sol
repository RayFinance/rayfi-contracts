// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    address ROUTER = makeAddr("router");

    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address dividendToken;
        address router;
    }

    error HelperConfig__ChainNotImplemented();

    constructor() {
        if (block.chainid == 11155111) {
            revert HelperConfig__ChainNotImplemented();
            // activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        // NetworkConfig memory sepoliaConfig = NetworkConfig({
        //     priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306
        // });
        // return sepoliaConfig;
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.dividendToken != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        address dividendToken = address(new ERC20Mock());
        vm.etch(ROUTER, vm.getCode("out/UniswapV2Router02.sol/UniswapV2Router02.json"));
        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({dividendToken: dividendToken, router: ROUTER});
        return anvilConfig;
    }
}
