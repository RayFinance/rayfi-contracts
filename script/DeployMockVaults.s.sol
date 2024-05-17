// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DeployMockVaults is Script {
    function run() external returns (address btcb, address eth, address bnb) {
        HelperConfig helper = new HelperConfig();
        (,, btcb, eth, bnb) = helper.activeNetworkConfig();
    }

    // Excludes contract from coverage report
    function test() public {}
}
