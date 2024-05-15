// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
// import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

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

        vm.etch(WETH, vm.getCode("out/WETH9.sol/WETH9.json"));
        // deployCodeTo("WETH9.sol:WETH9", WETH);

        bytes memory factoryArgs = abi.encode(msg.sender);
        bytes memory factoryBytecode =
            abi.encodePacked(vm.getCode("out/UniswapV2Factory.sol/UniswapV2Factory.json"), factoryArgs);
        address factoryDeployment;
        assembly {
            factoryDeployment := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }
        vm.etch(FACTORY, factoryDeployment.code);
        // deployCodeTo("UniswapV2Factory.sol:UniswapV2Factory", abi.encode(msg.sender), FACTORY);

        bytes memory routerArgs = abi.encode(FACTORY, WETH);
        bytes memory routerBytecode =
            abi.encodePacked(vm.getCode("out/UniswapV2Router02.sol/UniswapV2Router02.json"), routerArgs);
        address routerDeployment;
        assembly {
            routerDeployment := create(0, add(routerBytecode, 0x20), mload(routerBytecode))
        }
        vm.etch(ROUTER, routerDeployment.code);
        // deployCodeTo("UniswapV2Router02.sol:UniswapV2Router02", abi.encode(FACTORY, WETH), ROUTER);
        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({dividendToken: dividendToken, router: ROUTER});
        return anvilConfig;
    }

    // Excludes contract from coverage report
    function test() public {}
}
