// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RayFi} from "../../src/RayFi.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {DeployRayFi} from "../../script/DeployRayFi.s.sol";

contract Fuzz is Test {
    RayFi rayFi;

    uint160 public constant MINIMUM_TOKEN_BALANCE_FOR_REWARDS = 1_000 ether;
    uint8 public constant BUY_FEE = 4;
    uint8 public constant SELL_FEE = 4;
    uint8 public constant ACCEPTED_PRECISION_LOSS = 1;

    function setUp() external {
        DeployRayFi deployRayFi = new DeployRayFi();
        (rayFi,,) = deployRayFi.run();

        vm.startPrank(msg.sender);
        rayFi.setFeeAmounts(BUY_FEE, SELL_FEE);
        rayFi.setMinimumTokenBalanceForRewards(MINIMUM_TOKEN_BALANCE_FOR_REWARDS);
        vm.stopPrank();
    }

    function testFuzz_sumsArePreservedOnTransfers(address to, uint256 value) public {
        if (to == address(0)) {
            return;
        }

        value = bound(value, 0, rayFi.balanceOf(msg.sender));
        uint256 fromBalance = rayFi.balanceOf(msg.sender);
        uint256 toBalance = rayFi.balanceOf(to);
        uint256 totalSupply = rayFi.totalSupply();
        uint256 totalRewardShares = rayFi.getTotalRewardShares();
        uint256 fromBalanceAtSnapshot = rayFi.getBalanceOfAtSnapshot(msg.sender, 0);
        uint256 toBalanceAtSnapshot = rayFi.getBalanceOfAtSnapshot(to, 0);
        uint256 fromSharesBalance = rayFi.getSharesBalanceOf(msg.sender);
        uint256 toSharesBalance = rayFi.getSharesBalanceOf(to);
        uint256 totalRewardSharesAtSnapshot = rayFi.getTotalRewardSharesAtSnapshot(0);

        vm.prank(msg.sender);
        rayFi.transfer(to, value);

        uint256 valueReceived = value - value * (BUY_FEE + SELL_FEE) / 100;
        assertEq(rayFi.balanceOf(msg.sender), fromBalance - value);
        assertEq(rayFi.balanceOf(to), toBalance + valueReceived);
        assert(rayFi.totalSupply() >= totalSupply - ACCEPTED_PRECISION_LOSS);
        assert(rayFi.totalSupply() <= totalSupply);
        assertEq(rayFi.getCurrentSnapshotId(), 0);
        if (
            rayFi.balanceOf(msg.sender) >= MINIMUM_TOKEN_BALANCE_FOR_REWARDS
                && rayFi.balanceOf(to) >= MINIMUM_TOKEN_BALANCE_FOR_REWARDS
        ) {
            assertEq(rayFi.getBalanceOfAtSnapshot(msg.sender, 0), fromBalanceAtSnapshot - value);
            assertEq(rayFi.getSharesBalanceOf(msg.sender), fromSharesBalance - value);
            assertEq(rayFi.getBalanceOfAtSnapshot(to, 0), toBalanceAtSnapshot + valueReceived);
            assertEq(rayFi.getSharesBalanceOf(to), toSharesBalance + valueReceived);
            assert(
                rayFi.getTotalRewardShares()
                    >= totalRewardShares - value * (BUY_FEE + SELL_FEE) / 100 - ACCEPTED_PRECISION_LOSS
            );
            assert(rayFi.getTotalRewardShares() <= totalRewardShares - value * (BUY_FEE + SELL_FEE) / 100);
            assert(
                rayFi.getTotalRewardSharesAtSnapshot(0)
                    >= totalRewardSharesAtSnapshot - value * (BUY_FEE + SELL_FEE) / 100 - ACCEPTED_PRECISION_LOSS
            );
            assert(
                rayFi.getTotalRewardSharesAtSnapshot(0)
                    <= totalRewardSharesAtSnapshot - value * (BUY_FEE + SELL_FEE) / 100
            );
        } else if (rayFi.balanceOf(to) >= MINIMUM_TOKEN_BALANCE_FOR_REWARDS) {
            assertEq(rayFi.getBalanceOfAtSnapshot(msg.sender, 0), 0);
            assertEq(rayFi.getSharesBalanceOf(msg.sender), 0);
            assertEq(rayFi.getBalanceOfAtSnapshot(to, 0), toBalanceAtSnapshot + valueReceived);
            assertEq(rayFi.getSharesBalanceOf(to), toSharesBalance + valueReceived);
            assertEq(rayFi.getTotalRewardShares(), rayFi.balanceOf(to));
            assertEq(rayFi.getTotalRewardSharesAtSnapshot(0), rayFi.balanceOf(to));
        } else {
            assertEq(rayFi.getBalanceOfAtSnapshot(msg.sender, 0), fromBalanceAtSnapshot - value);
            assertEq(rayFi.getSharesBalanceOf(msg.sender), fromSharesBalance - value);
            assertEq(rayFi.getBalanceOfAtSnapshot(to, 0), 0);
            assertEq(rayFi.getSharesBalanceOf(to), 0);
            assertEq(rayFi.getTotalRewardShares(), rayFi.balanceOf(msg.sender));
            assertEq(rayFi.getTotalRewardSharesAtSnapshot(0), rayFi.balanceOf(msg.sender));
        }
    }

    function testFuzz_sumsArePreservedOnStaking(uint256 value) public {
        address to = rayFi.getVaultTokens()[0];
        value = bound(value, 0, rayFi.balanceOf(msg.sender));
        uint256 fromBalance = rayFi.balanceOf(msg.sender);
        uint256 totalSupply = rayFi.totalSupply();
        uint256 totalRewardShares = rayFi.getTotalRewardShares();
        uint256 fromBalanceAtSnapshot = rayFi.getBalanceOfAtSnapshot(msg.sender, 0);
        uint256 fromSharesBalance = rayFi.getSharesBalanceOf(msg.sender);
        uint256 totalRewardSharesAtSnapshot = rayFi.getTotalRewardSharesAtSnapshot(0);

        vm.prank(msg.sender);
        rayFi.stake(to, value);

        assertEq(rayFi.balanceOf(msg.sender), fromBalance - value);
        assertEq(rayFi.balanceOf(to), value);
        assertEq(rayFi.totalSupply(), totalSupply);
        assertEq(rayFi.getTotalRewardShares(), totalRewardShares);
        assertEq(rayFi.getTotalStakedShares(), value);
        assertEq(rayFi.getCurrentSnapshotId(), 0);
        assertEq(rayFi.getBalanceOfAtSnapshot(msg.sender, 0), fromBalanceAtSnapshot - value);
        assertEq(rayFi.getSharesBalanceOf(msg.sender), fromSharesBalance);
        assertEq(rayFi.getBalanceOfAtSnapshot(to, 0), 0);
        assertEq(rayFi.getSharesBalanceOf(to), 0);
        assertEq(rayFi.getTotalRewardShares(), totalRewardShares);
        assertEq(rayFi.getTotalRewardSharesAtSnapshot(0), totalRewardSharesAtSnapshot);
        assertEq(rayFi.getTotalStakedShares(), value);
        assertEq(rayFi.getTotalStakedSharesAtSnapshot(0), value);
        assertEq(rayFi.getVaultBalanceOf(to, msg.sender), value);
        assertEq(rayFi.getTotalVaultShares(to), value);

        vm.prank(msg.sender);
        rayFi.unstake(to, value);

        assertEq(rayFi.balanceOf(msg.sender), fromBalance);
        assertEq(rayFi.balanceOf(to), 0);
        assertEq(rayFi.totalSupply(), totalSupply);
        assertEq(rayFi.getTotalRewardShares(), totalRewardShares);
        assertEq(rayFi.getTotalStakedShares(), 0);
        assertEq(rayFi.getCurrentSnapshotId(), 0);
        assertEq(rayFi.getBalanceOfAtSnapshot(msg.sender, 0), fromBalanceAtSnapshot);
        assertEq(rayFi.getSharesBalanceOf(msg.sender), fromSharesBalance);
        assertEq(rayFi.getBalanceOfAtSnapshot(to, 0), 0);
        assertEq(rayFi.getSharesBalanceOf(to), 0);
        assertEq(rayFi.getTotalRewardShares(), totalRewardShares);
        assertEq(rayFi.getTotalRewardSharesAtSnapshot(0), totalRewardSharesAtSnapshot);
        assertEq(rayFi.getTotalStakedShares(), 0);
        assertEq(rayFi.getTotalStakedSharesAtSnapshot(0), 0);
        assertEq(rayFi.getVaultBalanceOf(to, msg.sender), 0);
        assertEq(rayFi.getTotalVaultShares(to), 0);
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
