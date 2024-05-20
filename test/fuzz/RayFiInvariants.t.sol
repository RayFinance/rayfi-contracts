// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployRayFi} from "../../script/DeployRayFi.s.sol";
import {RayFi} from "../../src/RayFi.sol";

contract Invariants is StdInvariant, Test {
    RayFi rayFi;

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address DIVIDEND_RECEIVER = makeAddr("dividendReceiver");

    function setUp() external {
        DeployRayFi deployRayFi = new DeployRayFi();
        (rayFi,,) = deployRayFi.run(FEE_RECEIVER, DIVIDEND_RECEIVER);
    }

    function invariant_gettersShouldNotRevert() public view {
        rayFi.getShareholders();
        rayFi.getSharesBalanceOf(msg.sender);
        rayFi.getStakedBalanceOf(msg.sender);
        rayFi.getTotalRewardShares();
        rayFi.getTotalStakedShares();
        rayFi.getVaultTokens();
        rayFi.getVaultBalanceOf(address(rayFi), msg.sender);
        rayFi.getTotalVaultShares(address(rayFi));
        rayFi.getMinimumTokenBalanceForRewards();
        rayFi.getCurrentSnapshotId();
        rayFi.getBalanceOfAtSnapshot(msg.sender, 0);
        rayFi.getTotalRewardSharesAtSnapshot(0);
        rayFi.getTotalStakedSharesAtSnapshot(0);
        rayFi.getRewardToken();
        rayFi.getFeeReceiver();
        rayFi.getAreTradingFeesEnabled();
        rayFi.getBuyFee();
        rayFi.getSellFee();
    }
}
