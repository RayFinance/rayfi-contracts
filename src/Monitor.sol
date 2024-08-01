// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {RayFi} from "./RayFi.sol";
import {Vault} from "./Vault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Monitor
 * @author 0xC4LL3
 * @notice Monitor contract to provide an interface to interact with the staked balance of a user
 * across RayFi and external vaults
 */
contract Monitor is Ownable {
    /////////////////////
    // State Variables //
    /////////////////////

    RayFi private rayFi;
    Vault[] private externalVaults;

    ////////////////
    /// Events    //
    ////////////////

    /**
     * @notice Emitted when the RayFi contract is updated
     * @param newRayFi The address of the new RayFi contract
     */
    event RayFiUpdated(address indexed newRayFi);

    /**
     * @notice Emitted when a new vault is added
     * @param newVault The address of the new vault
     */
    event VaultAdded(address indexed newVault);

    /**
     * @notice Emitted when a vault is removed
     * @param removedVault The address of the removed vault
     */
    event VaultRemoved(address indexed removedVault);

    //////////////////
    // Errors       //
    //////////////////

    /**
     * @dev Triggered when attempting to set the zero address as a contract parameter
     * Setting a contract parameter to the zero address can lead to unexpected behavior
     */
    error Monitor__CannotSetToZeroAddress();

    /**
     * @dev Triggered when trying to add a vault that already exists
     * @param vault The address that was passed as input
     */
    error Monitor__VaultAlreadyExists(address vault);

    /**
     * @dev Triggered when trying to remove a vault with an out-of-bound index
     * @param index The index that was passed as input
     */
    error Monitor__IndexOutOfBounds(uint256 index);

    ////////////////////
    // Constructor    //
    ////////////////////

    /**
     * @notice Constructor to initialize the contract with RayFi and external vaults
     * @param _rayFi The address of the RayFi contract
     * @param _externalVaults The addresses of the external vaults
     */
    constructor(RayFi _rayFi, Vault[] memory _externalVaults) Ownable(msg.sender) {
        if (address(_rayFi) == address(0)) {
            revert Monitor__CannotSetToZeroAddress();
        }
        for (uint256 i = 0; i < _externalVaults.length; ++i) {
            if (address(_externalVaults[i]) == address(0)) {
                revert Monitor__CannotSetToZeroAddress();
            }
        }

        rayFi = _rayFi;
        externalVaults = _externalVaults;
    }

    /**
     * @notice Sets the RayFi contract address
     * @param _rayFi The address of the RayFi contract
     */
    function setRayFi(RayFi _rayFi) external onlyOwner {
        if (address(_rayFi) == address(0)) {
            revert Monitor__CannotSetToZeroAddress();
        }

        rayFi = _rayFi;

        emit RayFiUpdated(address(rayFi));
    }

    /**
     * @notice Adds an external vault to the array of external vaults
     * @param newVault The external vault to add
     */
    function addExternalVault(Vault newVault) external onlyOwner {
        if (address(newVault) == address(0)) {
            revert Monitor__CannotSetToZeroAddress();
        }
        for (uint256 i = 0; i < externalVaults.length; ++i) {
            if (address(externalVaults[i]) == address(newVault)) {
                revert Monitor__VaultAlreadyExists(address(externalVaults[i]));
            }
        }

        externalVaults.push(newVault);

        emit VaultAdded(address(newVault));
    }

    /**
     * @notice Removes an external vault from the array of external vaults
     * @dev This function ensures no gaps are left in the array, but it modifies the order of its elements
     * @param index The index of the external vault to remove
     */
    function removeExternalVault(uint256 index) external onlyOwner {
        if (index >= externalVaults.length) {
            revert Monitor__IndexOutOfBounds(index);
        }

        Vault removedVault = externalVaults[index];
        if (index != externalVaults.length - 1) {
            externalVaults[index] = externalVaults[externalVaults.length - 1];
        }

        externalVaults.pop();

        emit VaultRemoved(address(removedVault));
    }

    /**
     * @notice Retrieves the staked balance of a user across RayFi and external vaults
     * @param user The address of the user
     * @return stakedBalance The staked balance of the user
     */
    function getStakedBalanceOf(address user) external view returns (uint256 stakedBalance) {
        stakedBalance = rayFi.getStakedBalanceOf(user);
        for (uint256 i = 0; i < externalVaults.length; ++i) {
            stakedBalance += externalVaults[i].maxWithdraw(user);
        }
    }

    /**
     * @notice Retrieves the address of the RayFi contract
     * @return The address of the RayFi contract
     */
    function getRayFi() external view returns (address) {
        return address(rayFi);
    }

    /**
     * @notice Retrieves the addresses of the external vaults
     * @return The addresses of the external vaults
     */
    function getExternalVaults() external view returns (address[] memory) {
        address[] memory vaults = new address[](externalVaults.length);
        for (uint256 i = 0; i < externalVaults.length; ++i) {
            vaults[i] = address(externalVaults[i]);
        }
        return vaults;
    }
}
