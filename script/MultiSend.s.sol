// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

contract MultiSend is Script {
    address constant TOKEN_ADDRESS = 0x17C7ebB15646a229c03032182877665CD4D4d085;

    address[7] internal receivers = [
        0xF961c12607bED81FeB776F5ACAb92CD925eE16f8,
        0x15CB9Eb3315665BC126C83A1672BFeF271d91994,
        0xf8419FE276521a05E31e5B77abd3C04e74ecb3D7,
        0x13A4AE07C4472cEee4cB85D03fd69A1b0cAAEd46,
        0xEA2d71E7E83eBA89aDa22C679B52f906bc6b09F4,
        0x5a6D506cac33c42c76a0dd2299953abB581A9eed,
        0xd913a658D23583136Ea74872A10052003D2649b1
    ];

    uint256[7] internal amounts = [
        396664710960000000000,
        278326861960000000000,
        220622561320000000000,
        191323371820000000000,
        187606100080000000000,
        45867830820000000000,
        22048563040000000000
    ];

    function run() external {
        vm.startBroadcast();
        for (uint256 i; i < receivers.length; ++i) {
            (bool success,) =
                TOKEN_ADDRESS.call(abi.encodeWithSignature("transfer(address,uint256)", receivers[i], amounts[i]));
            require(success, "transfer failed");
        }
        vm.stopBroadcast();
    }
}
