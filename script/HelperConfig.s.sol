// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
// import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockUSDT} from "../test/mocks/MockUSDT.sol";
import {MockBTCB} from "../test/mocks/MockBTCB.sol";
import {MockETH} from "../test/mocks/MockETH.sol";
import {MockBNB} from "../test/mocks/MockBNB.sol";

contract HelperConfig is Script {
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address FEE_RECEIVER = makeAddr("feeReceiver");
    address SWAP_RECEIVER = makeAddr("rewardReceiver");

    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address feeReceiver;
        address swapReceiver;
        address rewardToken;
        address router;
        address btcb;
        address eth;
        address bnb;
    }

    error HelperConfig__ChainNotImplemented();

    constructor() {
        if (block.chainid == 5611) {
            activeNetworkConfig = getOpBnbTestnetConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getOpBnbTestnetConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory opBnbConfig = NetworkConfig({
            feeReceiver: 0xad1bbd16655A91AF4B4C68959Fc2751B029c463D,
            swapReceiver: 0x9631CCd0eAE0720fAe74f133f0799c6e99a568F3,
            rewardToken: 0xb4e6031F3a95E737046370a05d9add865c3D9A3B,
            router: 0x0F707e7f6E3C45536cfa13b2186B76D30BaA0108,
            btcb: 0x67E93A67160DD2aE54f8Ef840D1BFDAda72e6b16,
            eth: 0xf77EEC3c0D006DCF22C7250C196b516B71AD4039,
            bnb: 0x881703b8A543cc2Fc24c38718F1F725B579381c4
        });
        return opBnbConfig;
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.rewardToken != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        address rewardToken = address(new MockUSDT());
        address wbtc = address(new MockBTCB());
        address weth = address(new MockETH());
        address bnb = address(new MockBNB());

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

        NetworkConfig memory anvilConfig = NetworkConfig({
            feeReceiver: FEE_RECEIVER,
            swapReceiver: SWAP_RECEIVER,
            rewardToken: rewardToken,
            router: ROUTER,
            btcb: wbtc,
            eth: weth,
            bnb: bnb
        });
        return anvilConfig;
    }

    // Excludes contract from coverage report
    function test() public {}
}
