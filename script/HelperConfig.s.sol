// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockUSDT} from "../test/mocks/MockUSDT.sol";
import {MockBTCB} from "../test/mocks/MockBTCB.sol";
import {MockETH} from "../test/mocks/MockETH.sol";
import {MockBNB} from "../test/mocks/MockBNB.sol";

contract HelperConfig is Script {
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
        address wbnb;
    }

    error HelperConfig__ChainNotImplemented();

    constructor() {
        if (block.chainid == 204) {
            activeNetworkConfig = getOpBnbMainnetConfig();
        }
        else if (block.chainid == 5611) {
            activeNetworkConfig = getOpBnbTestnetConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getOpBnbMainnetConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory opBnbConfig = NetworkConfig({
            feeReceiver: 0x36a663CA228399C7Ce3A027C0F94fd9995307835,
            swapReceiver: 0xC743F0f8dAD2b03f7C5c358eABaaC10e8C193D4f,
            rewardToken: 0x9e5AAC1Ba1a2e6aEd6b32689DFcF62A509Ca96f3,
            router: 0x8cFe327CEc66d1C090Dd72bd0FF11d690C33a2Eb,
            btcb: 0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2,
            eth: 0xE7798f023fC62146e8Aa1b36Da45fb70855a77Ea,
            wbnb: 0x4200000000000000000000000000000000000006
        });
        return opBnbConfig;
    }

    function getOpBnbTestnetConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory opBnbConfig = NetworkConfig({
            feeReceiver: 0xad1bbd16655A91AF4B4C68959Fc2751B029c463D,
            swapReceiver: 0x9631CCd0eAE0720fAe74f133f0799c6e99a568F3,
            rewardToken: 0xb4e6031F3a95E737046370a05d9add865c3D9A3B,
            router: 0x0F707e7f6E3C45536cfa13b2186B76D30BaA0108,
            btcb: 0x67E93A67160DD2aE54f8Ef840D1BFDAda72e6b16,
            eth: 0xf77EEC3c0D006DCF22C7250C196b516B71AD4039,
            wbnb: 0x881703b8A543cc2Fc24c38718F1F725B579381c4
        });
        return opBnbConfig;
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.rewardToken != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        address rewardToken = address(new MockUSDT());
        address btcb = address(new MockBTCB());
        address eth = address(new MockETH());
        address wbnb = address(new MockBNB());

        address weth;
        assembly {
            weth := create(0, add(weth, 0x20), mload(weth))
        }

        bytes memory factoryArgs = abi.encode(msg.sender);
        bytes memory factoryBytecode =
            abi.encodePacked(vm.getCode("out/UniswapV2Factory.sol/UniswapV2Factory.json"), factoryArgs);
        address factory;
        assembly {
            factory := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }

        bytes memory routerArgs = abi.encode(factory, weth);
        bytes memory routerBytecode =
            abi.encodePacked(vm.getCode("out/UniswapV2Router02.sol/UniswapV2Router02.json"), routerArgs);
        address router;
        assembly {
            router := create(0, add(routerBytecode, 0x20), mload(routerBytecode))
        }
        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({
            feeReceiver: FEE_RECEIVER,
            swapReceiver: SWAP_RECEIVER,
            rewardToken: rewardToken,
            router: router,
            btcb: btcb,
            eth: eth,
            wbnb: wbnb
        });
        return anvilConfig;
    }

    // Excludes contract from coverage report
    function test() public {}
}
