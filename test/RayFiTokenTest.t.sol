// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployRayFiToken} from "../script/DeployRayFiToken.s.sol";
import {RayFiToken} from "../src/RayFiToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract RayFiTokenTest is Test {
    RayFiToken rayFiToken;
    ERC20Mock dividendToken;
    IUniswapV2Router02 router;

    uint256 public constant INITIAL_RAYFI_LIQUIDITY = 2_858_550 * (10 ** 18);
    uint256 public constant INITIAL_DIVIDEND_LIQUIDITY = 14_739 * (10 ** 18);
    uint256 public constant TRANSFER_AMOUNT = 1000;

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address DIVIDEND_RECEIVER = makeAddr("dividendReceiver");

    function setUp() external {
        DeployRayFiToken deployRayFiToken = new DeployRayFiToken();
        (rayFiToken, dividendToken, router) = deployRayFiToken.run(FEE_RECEIVER, DIVIDEND_RECEIVER);

        vm.startPrank(msg.sender);
        dividendToken.mint(msg.sender, INITIAL_DIVIDEND_LIQUIDITY);

        rayFiToken.approve(address(router), INITIAL_RAYFI_LIQUIDITY);
        dividendToken.approve(address(router), INITIAL_DIVIDEND_LIQUIDITY);

        router.addLiquidity(
            address(rayFiToken),
            address(dividendToken),
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_DIVIDEND_LIQUIDITY,
            0,
            0,
            address(this),
            block.timestamp
        );
        vm.stopPrank();
    }

    function testWasSetUpCorrectly() public view {
        assertEq(address(rayFiToken.owner()), msg.sender);
        assertEq(rayFiToken.balanceOf(msg.sender), rayFiToken.totalSupply() - INITIAL_RAYFI_LIQUIDITY);
        assertEq(rayFiToken.getFeeReceiver(), FEE_RECEIVER);
        assert(IUniswapV2Factory(router.factory()).getPair(address(rayFiToken), address(dividendToken)) != address(0));
    }

    function testWalletToWalletTransfersWork() public {
        vm.startPrank(msg.sender);
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);
        vm.stopPrank();

        assertEq(rayFiToken.balanceOf(address(this)), TRANSFER_AMOUNT);
    }
}
