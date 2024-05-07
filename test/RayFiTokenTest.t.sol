// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RayFiToken, ERC20} from "../src/RayFiToken.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {DeployRayFiToken} from "../script/DeployRayFiToken.s.sol";

contract RayFiTokenTest is Test {
    RayFiToken rayFiToken;
    ERC20 dividendToken;
    IUniswapV2Router02 router;

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address DIVIDEND_RECEIVER = makeAddr("dividendReceiver");

    function setUp() external {
        DeployRayFiToken deployRayFiToken = new DeployRayFiToken();
        (rayFiToken, dividendToken, router) = deployRayFiToken.run(FEE_RECEIVER, DIVIDEND_RECEIVER);
    }

    function testWasSetUpCorrectly() public view {
        assertEq(address(rayFiToken.owner()), msg.sender);
        assertEq(rayFiToken.getFeeReceiver(), FEE_RECEIVER);
        assertEq(rayFiToken.balanceOf(msg.sender), rayFiToken.totalSupply());
    }
}
