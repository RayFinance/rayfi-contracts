// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {RayFi} from "./RayFi.sol";
import {Vault} from "./Vault.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";

/**
 * @title StakingWallet
 * @author 0xC4LL3
 * @notice Vesting wallet with RayFi staking capabilities
 */
contract StakingWallet is VestingWallet {
    RayFi private rayFi;
    address[] private externalVaults;

    /**
     * @notice Triggered when trying to stake in a vault that is not supported
     */
    error StakingWallet__VaultNotSupported(address vaultToken);

    /**
     * @param _rayFi RayFi contract address
     * @param _externalVaults External vaults addresses
     * @param beneficiary Beneficiary address
     * @param startTimestamp Vesting start timestamp
     * @param durationSeconds Vesting duration in seconds
     */
    constructor(
        address _rayFi,
        address[] memory _externalVaults,
        address beneficiary,
        uint64 startTimestamp,
        uint64 durationSeconds
    ) VestingWallet(beneficiary, startTimestamp, durationSeconds) {
        rayFi = RayFi(_rayFi);
        externalVaults = _externalVaults;
    }

    /**
     * @notice Stake vested tokens
     * @param vaultToken The vault token address, either integrated in RayFi or external
     * @param amount The amount to stake
     */
    function stake(address vaultToken, uint256 amount) external onlyOwner {
        address[] memory vaultTokens = rayFi.getVaultTokens();
        for (uint256 i; i < vaultTokens.length; ++i) {
            if (vaultTokens[i] == vaultToken) {
                rayFi.stake(vaultToken, amount);
                return;
            }
        }
        for (uint256 i; i < externalVaults.length; ++i) {
            if (externalVaults[i] == vaultToken) {
                rayFi.approve(vaultToken, amount);
                Vault(vaultToken).deposit(amount, address(this));
                return;
            }
        }
        revert StakingWallet__VaultNotSupported(vaultToken);
    }

    /**
     * @notice Unstake vested tokens
     * @param vaultToken The vault token address, either integrated in RayFi or external
     * @param amount The amount to unstake
     */
    function unstake(address vaultToken, uint256 amount) external onlyOwner {
        address[] memory vaultTokens = rayFi.getVaultTokens();
        for (uint256 i; i < vaultTokens.length; ++i) {
            if (vaultTokens[i] == vaultToken) {
                rayFi.unstake(vaultToken, amount);
                return;
            }
        }
        for (uint256 i; i < externalVaults.length; ++i) {
            if (externalVaults[i] == vaultToken) {
                Vault(vaultToken).withdraw(amount, address(this), address(this));
                return;
            }
        }
        revert StakingWallet__VaultNotSupported(vaultToken);
    }

    // Excludes contract from coverage report
    function test() public {}
}
