// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployRayFi} from "../../script/DeployRayFi.s.sol";
import {AirdropRayFi} from "../../script/AirdropRayFi.s.sol";
import {RayFi} from "../../src/RayFi.sol";

contract AirdropRayFiTest is Test {
    RayFi rayFi;
    AirdropRayFi airdropRayFi;

    function setUp() public {
        (rayFi,,,) = new DeployRayFi().run();
        airdropRayFi = new AirdropRayFi();
    }

    function testAirdropWorked() public {
        uint256 totalAmount = airdropRayFi.TOTAL_AMOUNT();
        address[] memory addresses = airdropRayFi.getAddresses();
        uint256[] memory amounts = airdropRayFi.getAmounts();

        airdropRayFi.airdropRayFi(rayFi, true);

        uint256 actualTotalAmount;
        for (uint256 i; i < addresses.length; ++i) {
            assertEq(rayFi.balanceOf(addresses[i]), amounts[i]);
            actualTotalAmount += amounts[i];
        }
        assertEq(actualTotalAmount, totalAmount);
    }
}
