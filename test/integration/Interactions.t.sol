// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RayFi} from "../../src/RayFi.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {DeployRayFi} from "../../script/DeployRayFi.s.sol";
import {DeployMockVaults} from "../../script/DeployMockVaults.s.sol";
import {
    FundRayFi,
    CreateRayFiLiquidityPool,
    CreateRayFiUsers,
    FullyStakeRayFiUsersSingleVault,
    PartiallyStakeRayFiUsersSingleVault,
    AddMockRayFiVaults,
    FullyStakeRayFiUsersMultipleVaults,
    PartiallyStakeRayFiUsersMultipleVaults
} from "../../script/Interactions.s.sol";

contract InteractionsTest is Test {
    RayFi rayFi;
    ERC20Mock rewardToken;
    IUniswapV2Router02 router;
    ERC20Mock btcb;
    ERC20Mock eth;
    ERC20Mock bnb;

    uint256 constant FUND_AMOUNT = 10_000 ether;
    uint256 constant INITIAL_RAYFI_LIQUIDITY = 2_858_550 ether;
    uint256 constant INITIAL_REWARD_LIQUIDITY = 14_739 ether;
    uint256 constant USDT_LIQUIDITY = 1_000_000 ether;
    uint256 constant BTCB_LIQUIDITY = 100 ether;
    uint256 constant ETH_LIQUIDITY = 1_000 ether;
    uint256 constant BNB_LIQUIDITY = 10_000 ether;
    uint256 constant USER_COUNT = 100;
    uint256 constant MAX_ATTEMPTS = 100;
    uint32 public constant GAS_FOR_REWARDS = 1_000_000;
    uint8 constant ACCEPTED_PRECISION_LOSS = 100;

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address SWAP_RECEIVER = makeAddr("rewardReceiver");

    function setUp() public {
        DeployRayFi deployRayFi = new DeployRayFi();
        (rayFi, rewardToken, router) = deployRayFi.run(FEE_RECEIVER, SWAP_RECEIVER);

        DeployMockVaults deployMockVaults = new DeployMockVaults();
        (address btcbAddress, address ethAddress, address bnbAddress) = deployMockVaults.run();
        btcb = ERC20Mock(btcbAddress);
        eth = ERC20Mock(ethAddress);
        bnb = ERC20Mock(bnbAddress);
    }

    function testFundRayFi() public {
        FundRayFi fundRayFi = new FundRayFi();
        fundRayFi.fundRayFi(address(rayFi));

        assertEq(rewardToken.balanceOf(address(rayFi)), FUND_AMOUNT);
    }
