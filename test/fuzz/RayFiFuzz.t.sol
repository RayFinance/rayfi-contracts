// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RayFi} from "../../src/RayFi.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {DeployRayFi} from "../../script/DeployRayFi.s.sol";

contract Fuzz is Test {
    RayFi rayFi;

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address SWAP_RECEIVER = makeAddr("rewardReceiver");

    uint160 public constant MINIMUM_TOKEN_BALANCE_FOR_REWARDS = 1_000 ether;
    uint8 public constant BUY_FEE = 4;
    uint8 public constant SELL_FEE = 4;
    uint8 public constant ACCEPTED_PRECISION_LOSS = 1;

    function setUp() external {
        DeployRayFi deployRayFi = new DeployRayFi();
        (rayFi,,) = deployRayFi.run(FEE_RECEIVER, SWAP_RECEIVER);

        vm.startPrank(msg.sender);
        rayFi.setFeeAmounts(BUY_FEE, SELL_FEE);
        rayFi.setMinimumTokenBalanceForRewards(MINIMUM_TOKEN_BALANCE_FOR_REWARDS);
        vm.stopPrank();
    }

    function testFuzz_cannotTransferMoreThanOwned(uint256 value) public {
        if (value == 0) {
            return;
        }
        vm.expectRevert();
        rayFi.transfer(msg.sender, value);
    }

    function testFuzz_cannotTransferFromMoreThanAllowed(address from, uint256 value) public {
        if (value == 0) {
            return;
        }
        vm.expectRevert();
        rayFi.transferFrom(from, address(rayFi), value);
    }

    function testFuzz_cannotStakeMoreThanOwned(uint256 value) public {
        if (value == 0) {
            return;
        }
        vm.expectRevert();
        rayFi.stake(address(rayFi), value);
    }

    function testFuzz_cannotUnstakeMoreThanOwned(uint256 value) public {
        if (value == 0) {
            return;
        }
        vm.expectRevert();
        rayFi.unstake(address(rayFi), value);
    }
}
