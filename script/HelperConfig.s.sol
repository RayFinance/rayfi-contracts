// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {UniswapV2Factory} from "@uniswap/v2-core/contracts/UniswapV2Factory.sol";
import {UniswapV2Router02} from "@uniswap/v2-periphery/contracts/UniswapV2Router02.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address dividendToken;
        address weth;
        address factory;
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
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        ERC20Mock dividendToken = new ERC20Mock("Dividend Token", "DIV");
        ERC20Mock weth = new ERC20Mock("Wrapped Ether", "WETH");
        UniswapV2Factory factory = new UniswapV2Factory(msg.sender);
        UniswapV2Router02 router = new UniswapV2Router02(address(factory), address(weth));
        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({
            dividendToken: address(dividendToken),
            weth: address(weth),
            factory: address(factory),
            router: address(router)
        });
        return anvilConfig;
    }
}
