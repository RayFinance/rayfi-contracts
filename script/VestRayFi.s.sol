// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {DeployRayFi} from "./DeployRayFi.s.sol";
import {RayFi} from "../src/RayFi.sol";
import {Vault} from "../src/Vault.sol";
import {StakingWallet} from "../src/StakingWallet.sol";

contract VestRayFi is Script {
    uint160 private constant VESTED_AMOUNT_TEAM = 100_000 ether;
    uint160 private constant VESTED_AMOUNT_ONE = 180_000 ether;
    uint160 private constant UNLOCKED_AMOUNT_TEAM = 10_000 ether;
    uint160 private constant UNLOCKED_AMOUNT_ONE = 20_000 ether;

    address private oneWallet = 0x66497a5C1D8463B00F330a2eC0609D074B18817A;

    address[5] private teamWallets = [
        0x2EA6920992982191491a340E1e983192F351882D,
        0x265eb533724CD995170B66FE40Ae2bB9d11E3E13,
        0xb58A3CF44f3A872dEA81bC0a3F6bE7a853e0f3bB,
        0xFF05c70617aCe7b8422888ecd613ed715B7bDC5A,
        0xC6FB6d9673a9B1A5E113D55241b13668648e216c
    ];

    function run() public {
        RayFi rayFi;
        if (block.chainid == 204) {
            rayFi = RayFi(0xA9c72Fed4327418CeEA0b8611779b48F3Ca03D8b);
        } else if (block.chainid == 5611) {
            rayFi = RayFi(0x290E65E2c7E595DD61357159dC8672F1C26626cf);
        } else {
            (rayFi,,,) = new DeployRayFi().run();
        }

        vm.startBroadcast();

        address[] memory externalVaults = new address[](3);
        if (block.chainid == 204) {
            externalVaults[0] = 0x4bE042c0C69D809B8D739369515A1Ee7d4DFFBc7;
            externalVaults[1] = 0x90e740e082f4a2743B5054CEC4F2a82eE7A32A91;
            externalVaults[2] = 0xcbaC8d0976E850c49Cf9B4e2E2faCcC0df28a299;
        } else {
            externalVaults[0] = address(new Vault(address(rayFi), "ONE Vault", "ONE_VAULT"));
            externalVaults[1] = address(new Vault(address(rayFi), "THREE Vault", "THREE_VAULT"));
            externalVaults[2] = address(new Vault(address(rayFi), "FOUR Vault", "FOUR_VAULT"));
            for (uint256 i; i < externalVaults.length; ++i) {
                rayFi.setIsFeeExempt(externalVaults[i], true);
                rayFi.setIsExcludedFromRewards(externalVaults[i], true);
            }
        }

        StakingWallet stakingWallet;
        for (uint256 i; i < teamWallets.length; ++i) {
            stakingWallet =
                new StakingWallet(address(rayFi), externalVaults, teamWallets[i], uint64(1722096250), 7_776_000);
            rayFi.setIsFeeExempt(address(stakingWallet), true);
            rayFi.transfer(teamWallets[i], UNLOCKED_AMOUNT_TEAM);
            rayFi.transfer(address(stakingWallet), VESTED_AMOUNT_TEAM);
        }
        stakingWallet = new StakingWallet(address(rayFi), externalVaults, oneWallet, uint64(1722096250), 7_776_000);
        rayFi.setIsFeeExempt(address(stakingWallet), true);
        rayFi.transfer(oneWallet, UNLOCKED_AMOUNT_ONE);
        rayFi.transfer(address(stakingWallet), VESTED_AMOUNT_ONE);

        vm.stopBroadcast();
    }

    // Excludes contract from coverage report
    function test() public {}
}
