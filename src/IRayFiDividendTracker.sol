// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IRayFiDividendTracker {
    /**
     * @notice Sets the dividend balance of an account and processes its dividends
     * @dev Calls the `processAccount` function
     */
    function setBalance(address account, uint256 newBalance) external;

    /**
     * @notice Swaps accrued fees for stablecoin after a threshold is reached
     */
    function swapFees() external;

    /**
     * @notice Makes an address ineligible for dividends
     * @dev Calls `_setBalance` and updates `tokenHoldersMap` iterable mapping
     */
    function excludeFromDividends(address account) external;
}
