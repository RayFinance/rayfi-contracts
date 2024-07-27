// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/**
 * @title Vault
 * @author 0xC4LL3
 * @notice Minimal vault implementation to be used for off-chain management by querying past blocks
 */
contract Vault is ERC4626 {
    /**
     * @param asset Vault underlying asset
     * @param name Vault name
     * @param symbol Vault symbol
     */
    constructor(address asset, string memory name, string memory symbol) ERC4626(ERC20(asset)) ERC20(name, symbol) {}
}
