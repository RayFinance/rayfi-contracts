// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployRayFi} from "../../script/DeployRayFi.s.sol";
// import {RayFi} from "../../src/RayFi.sol";

// contract Invariants is StdInvariant, Test {
//     RayFi rayFi;

//     address FEE_RECEIVER = makeAddr("feeReceiver");
//     address DIVIDEND_RECEIVER = makeAddr("dividendReceiver");

//     function setUp() external {
//         DeployRayFi deployRayFi = new DeployRayFi();
//         (rayFi,,) = deployRayFi.run(FEE_RECEIVER, DIVIDEND_RECEIVER);
//     }

//     function invariant_gettersShouldNotRevert() public view {
//         rayFi.getShareholders();
//         rayFi.getSharesBalanceOf(msg.sender);
//         rayFi.getStakedBalanceOf(msg.sender);
//         rayFi.getTotalStakedAmount();
//         rayFi.getMinimumTokenBalanceForDividends();
//         rayFi.getDividendToken();
//         rayFi.getFeeReceiver();
//         rayFi.getBuyFee();
//         rayFi.getSellFee();
//     }
// }
