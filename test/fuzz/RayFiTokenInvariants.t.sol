// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployRayFiToken} from "../../script/DeployRayFiToken.s.sol";
import {RayFiToken} from "../../src/RayFiToken.sol";

contract Invariants is StdInvariant, Test {
    RayFiToken rayFiToken;

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address DIVIDEND_RECEIVER = makeAddr("dividendReceiver");

    function setUp() external {
        DeployRayFiToken deployRayFiToken = new DeployRayFiToken();
        (rayFiToken,,) = deployRayFiToken.run(FEE_RECEIVER, DIVIDEND_RECEIVER);
    }

    function invariant_gettersShouldNotRevert() public view {
        rayFiToken.getShareholders();
        rayFiToken.getStakedBalanceOf(msg.sender);
        rayFiToken.getTotalStakedAmount();
        rayFiToken.getTotalDividendsDistributed();
        rayFiToken.getFeeReceiver();
        rayFiToken.getBuyFee();
        rayFiToken.getSellFee();
    }
}
