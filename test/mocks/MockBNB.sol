// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MockBNB is ERC20Mock {
    uint256 private constant TOTAL_SUPPLY = 100_000_000 ether;

    constructor() ERC20Mock() {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    // Excludes the contract from test coverage
    function test() public {}
}
