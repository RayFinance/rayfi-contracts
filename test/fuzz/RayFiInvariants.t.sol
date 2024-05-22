// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployRayFi} from "../../script/DeployRayFi.s.sol";
import {DeployMockVaults} from "../../script/DeployMockVaults.s.sol";
import {RayFi} from "../../src/RayFi.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    RayFi rayFi;
    ERC20Mock rewardToken;
    IUniswapV2Router02 router;

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address DIVIDEND_RECEIVER = makeAddr("dividendReceiver");

    uint256 public constant INITIAL_RAYFI_LIQUIDITY = 2_858_550 ether;
    uint256 public constant INITIAL_REWARD_LIQUIDITY = 14_739 ether;
    uint256 constant USDT_LIQUIDITY = 1_000_000 ether;
    uint256 constant BTCB_LIQUIDITY = 100 ether;
    uint256 constant ETH_LIQUIDITY = 1_000 ether;
    uint256 constant BNB_LIQUIDITY = 10_000 ether;
    uint160 public constant MINIMUM_TOKEN_BALANCE_FOR_REWARDS = 1_000 ether;
    uint8 public constant BUY_FEE = 4;
    uint8 public constant SELL_FEE = 4;

    function setUp() external {
        DeployRayFi deployRayFi = new DeployRayFi();
        (rayFi, rewardToken, router) = deployRayFi.run(FEE_RECEIVER, DIVIDEND_RECEIVER);

        DeployMockVaults deployMockVaults = new DeployMockVaults();
        (address btcb, address eth, address bnb) = deployMockVaults.run();

        rewardToken.mint(msg.sender, INITIAL_REWARD_LIQUIDITY);

        vm.startPrank(msg.sender);
        rayFi.approve(address(router), INITIAL_RAYFI_LIQUIDITY);
        rewardToken.approve(address(router), INITIAL_REWARD_LIQUIDITY);
        router.addLiquidity(
            address(rayFi),
            address(rewardToken),
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_REWARD_LIQUIDITY,
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_REWARD_LIQUIDITY,
            address(this),
            block.timestamp
        );
        address pair = IUniswapV2Factory(router.factory()).getPair(address(rayFi), address(rewardToken));
        rayFi.setIsAutomatedMarketPair(pair, true);
        rayFi.setIsExcludedFromRewards(pair, true);
        rayFi.setFeeAmounts(BUY_FEE, SELL_FEE);
        rayFi.setMinimumTokenBalanceForRewards(MINIMUM_TOKEN_BALANCE_FOR_REWARDS);

        address[3] memory vaultTokens = [address(btcb), address(eth), address(bnb)];
        uint256[3] memory vaultLiquidity = [BTCB_LIQUIDITY, ETH_LIQUIDITY, BNB_LIQUIDITY];
        for (uint256 i; i < 3; i++) {
            ERC20Mock(vaultTokens[i]).mint(msg.sender, vaultLiquidity[i]);

            ERC20Mock(vaultTokens[i]).approve(address(router), vaultLiquidity[i]);
            rewardToken.approve(address(router), USDT_LIQUIDITY);

            router.addLiquidity(
                address(rewardToken),
                vaultTokens[i],
                USDT_LIQUIDITY,
                vaultLiquidity[i],
                USDT_LIQUIDITY,
                vaultLiquidity[i],
                msg.sender,
                block.timestamp
            );
        }
        rayFi.addVault(address(btcb));
        rayFi.addVault(address(eth));
        rayFi.addVault(address(bnb));

        rayFi.setIsFeeExempt(msg.sender, true);
        vm.stopPrank();

        Handler handler = new Handler(rayFi, rewardToken, router, ERC20Mock(btcb), ERC20Mock(eth), ERC20Mock(bnb));
        targetContract(address(handler));

        vm.startPrank(msg.sender);
        rayFi.transfer(address(handler), rayFi.balanceOf(msg.sender));
        rayFi.setIsFeeExempt(address(handler), true);
        vm.stopPrank();
    }

    function invariant_protocolShouldHaveMoreSupplyThanSharesAndMoreTotalThanStakedShares() public view {
        uint256 totalTokenSupply = rayFi.totalSupply();
        uint256 totalRewardShares = rayFi.getTotalRewardShares();
        uint256 totalStakedShares = rayFi.getTotalStakedShares();
        assert(totalTokenSupply >= totalRewardShares);
        assert(totalRewardShares >= totalStakedShares);
    }

    function invariant_gettersShouldNotRevert() public view {
        rayFi.getShareholders();
        rayFi.getSharesBalanceOf(msg.sender);
        rayFi.getStakedBalanceOf(msg.sender);
        rayFi.getTotalRewardShares();
        rayFi.getTotalStakedShares();
        rayFi.getVaultTokens();
        rayFi.getVaultBalanceOf(address(rayFi), msg.sender);
        rayFi.getTotalVaultShares(address(rayFi));
        rayFi.getMinimumTokenBalanceForRewards();
        rayFi.getCurrentSnapshotId();
        rayFi.getBalanceOfAtSnapshot(msg.sender, 0);
        rayFi.getTotalRewardSharesAtSnapshot(0);
        rayFi.getTotalStakedSharesAtSnapshot(0);
        rayFi.getRewardToken();
        rayFi.getFeeReceiver();
        rayFi.getAreTradingFeesEnabled();
        rayFi.getBuyFee();
        rayFi.getSellFee();
    }

    // Excludes contract from coverage report
    function test() public {}
}
