// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RayFi} from "../../src/RayFi.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {DeployRayFi} from "../../script/DeployRayFi.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
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
    HelperConfig helperConfig;
    ERC20Mock btcb;
    ERC20Mock eth;
    ERC20Mock bnb;
    address[3] vaultTokens;

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

    function setUp() public {
        (rayFi, rewardToken, router, helperConfig) = new DeployRayFi().run();
        vm.prank(msg.sender);
        rayFi.setIsExcludedFromRewards(msg.sender, true);

        (,,,, address btcbAddress, address ethAddress, address bnbAddress) = helperConfig.activeNetworkConfig();
        btcb = ERC20Mock(btcbAddress);
        eth = ERC20Mock(ethAddress);
        bnb = ERC20Mock(bnbAddress);
        vaultTokens = [btcbAddress, ethAddress, bnbAddress];
    }

    function testFundRayFi() public {
        new FundRayFi().fundRayFi(address(rayFi));

        assertEq(rewardToken.balanceOf(address(rayFi)), FUND_AMOUNT);
    }

    function testCreateRayFiLiquidityPool() public {
        new CreateRayFiLiquidityPool().createRayFiLiquidityPool(
            address(rayFi), address(rewardToken), address(router), true
        );

        assert(
            IUniswapV2Factory(IUniswapV2Router02(router).factory()).getPair(address(rayFi), address(rewardToken))
                != address(0)
        );
    }

    function testCreateRayFiUsers() public {
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);

        assertEq(rayFi.getShareholders().length, USER_COUNT);
    }

    function testFullyStakeRayFiUsersSingleVault() public {
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);
        new FullyStakeRayFiUsersSingleVault().fullyStakeRayFiUsers(address(rayFi));

        assertEq(rayFi.getTotalRewardShares(), rayFi.getTotalStakedShares());
    }

    function testPartiallyStakeRayFiUsersSingleVault() public {
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);
        new PartiallyStakeRayFiUsersSingleVault().partiallyStakeRayFiUsers(address(rayFi));

        assertEq(rayFi.getTotalRewardShares() / 2, rayFi.getTotalStakedShares());
    }

    function testAddMockRayFiVaults() public {
        new AddMockRayFiVaults().addMockRayFiVaults(
            address(rayFi), address(rewardToken), address(btcb), address(eth), address(bnb), address(router), true
        );

        vm.startPrank(msg.sender);
        for (uint256 i; i < vaultTokens.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(RayFi.RayFi__VaultAlreadyExists.selector, vaultTokens[i]));
            rayFi.addVault(vaultTokens[i]);
        }
        vm.stopPrank();
    }

    function testFullyStakeRayFiUsersMultipleVaults() public {
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);
        new AddMockRayFiVaults().addMockRayFiVaults(
            address(rayFi), address(rewardToken), address(btcb), address(eth), address(bnb), address(router), true
        );
        new FullyStakeRayFiUsersMultipleVaults().fullyStakeRayFiUsersMultipleVaults(address(rayFi), vaultTokens);

        assertEq(rayFi.getTotalRewardShares(), rayFi.getTotalStakedShares());
    }

    function testPartiallyStakeRayFiUsersMultipleVaults() public {
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);
        new AddMockRayFiVaults().addMockRayFiVaults(
            address(rayFi), address(rewardToken), address(btcb), address(eth), address(bnb), address(router), true
        );
        new PartiallyStakeRayFiUsersMultipleVaults().partiallyStakeRayFiUsersMultipleVaults(address(rayFi), vaultTokens);

        assert(
            rayFi.getTotalStakedShares()
                >= rayFi.getTotalRewardShares() / 2 - ACCEPTED_PRECISION_LOSS * USER_COUNT * vaultTokens.length
                && rayFi.getTotalStakedShares()
                    <= rayFi.getTotalRewardShares() / 2 + ACCEPTED_PRECISION_LOSS * USER_COUNT * vaultTokens.length
        );
    }

    function testDistributionNoVaults() public {
        new FundRayFi().fundRayFi(address(rayFi));
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);

        vm.startPrank(msg.sender);
        rayFi.snapshot();
        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();

        address[] memory users = rayFi.getShareholders();
        for (uint256 i; i < users.length; ++i) {
            assert(rewardToken.balanceOf(users[i]) >= FUND_AMOUNT / (users.length) - ACCEPTED_PRECISION_LOSS);
        }
    }

    function testDistributionOnlySingleVault() public {
        new FundRayFi().fundRayFi(address(rayFi));
        new CreateRayFiLiquidityPool().createRayFiLiquidityPool(
            address(rayFi), address(rewardToken), address(router), true
        );
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);
        new FullyStakeRayFiUsersSingleVault().fullyStakeRayFiUsers(address(rayFi));

        address[] memory users = rayFi.getShareholders();
        uint256[] memory stakedBalancesBefore = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }

        vm.startPrank(msg.sender);
        rayFi.snapshot();
        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(FUND_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < users.length; ++i) {
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / users.length - ACCEPTED_PRECISION_LOSS
            );
        }
    }

    function testMixedDistributionSingleVault() public {
        new FundRayFi().fundRayFi(address(rayFi));
        new CreateRayFiLiquidityPool().createRayFiLiquidityPool(
            address(rayFi), address(rewardToken), address(router), true
        );
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);
        new PartiallyStakeRayFiUsersSingleVault().partiallyStakeRayFiUsers(address(rayFi));

        address[] memory users = rayFi.getShareholders();
        uint256[] memory stakedBalancesBefore = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }

        vm.startPrank(msg.sender);
        rayFi.snapshot();
        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();

        uint256 amountOut = router.getAmountOut(FUND_AMOUNT, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        for (uint256 i; i < users.length; ++i) {
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOut / (users.length * 2) - ACCEPTED_PRECISION_LOSS
            );
        }
        for (uint256 i; i < users.length; ++i) {
            assert(rewardToken.balanceOf(users[i]) >= FUND_AMOUNT / (users.length * 2) - ACCEPTED_PRECISION_LOSS);
        }
    }

    function testDistributionOnlyMultipleVaults() public {
        new FundRayFi().fundRayFi(address(rayFi));
        new CreateRayFiLiquidityPool().createRayFiLiquidityPool(
            address(rayFi), address(rewardToken), address(router), true
        );
        new AddMockRayFiVaults().addMockRayFiVaults(
            address(rayFi), address(rewardToken), address(btcb), address(eth), address(bnb), address(router), true
        );
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);
        new FullyStakeRayFiUsersMultipleVaults().fullyStakeRayFiUsersMultipleVaults(address(rayFi), vaultTokens);

        address[] memory users = rayFi.getShareholders();
        uint256[] memory stakedBalancesBefore = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }

        vm.startPrank(msg.sender);
        rayFi.snapshot();
        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();

        uint256 amountOutRayFi = router.getAmountOut(FUND_AMOUNT / 4, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        uint256 amountOutBTCB = router.getAmountOut(FUND_AMOUNT / 4, USDT_LIQUIDITY, BTCB_LIQUIDITY);
        uint256 amountOutETH = router.getAmountOut(FUND_AMOUNT / 4, USDT_LIQUIDITY, ETH_LIQUIDITY);
        uint256 amountOutBNB = router.getAmountOut(FUND_AMOUNT / 4, USDT_LIQUIDITY, BNB_LIQUIDITY);
        for (uint256 i; i < users.length; ++i) {
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOutRayFi / users.length - ACCEPTED_PRECISION_LOSS
            );
            assert(btcb.balanceOf(users[i]) >= amountOutBTCB / users.length - ACCEPTED_PRECISION_LOSS);
            assert(eth.balanceOf(users[i]) >= amountOutETH / users.length - ACCEPTED_PRECISION_LOSS);
            assert(bnb.balanceOf(users[i]) >= amountOutBNB / users.length - ACCEPTED_PRECISION_LOSS);
        }
    }

    function testMixedDistributionMultipleVaultsStateless() public {
        new FundRayFi().fundRayFi(address(rayFi));
        new CreateRayFiLiquidityPool().createRayFiLiquidityPool(
            address(rayFi), address(rewardToken), address(router), true
        );
        new AddMockRayFiVaults().addMockRayFiVaults(
            address(rayFi), address(rewardToken), address(btcb), address(eth), address(bnb), address(router), true
        );
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);
        new PartiallyStakeRayFiUsersMultipleVaults().partiallyStakeRayFiUsersMultipleVaults(address(rayFi), vaultTokens);

        address[] memory users = rayFi.getShareholders();
        uint256[] memory stakedBalancesBefore = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }
        uint256 deployerBalanceBefore = rewardToken.balanceOf(msg.sender);

        vm.startPrank(msg.sender);
        rayFi.snapshot();
        rayFi.distributeRewardsStateless(0);
        vm.stopPrank();

        uint256 amountOutRayFi = router.getAmountOut(FUND_AMOUNT / 8, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        uint256 amountOutBTCB = router.getAmountOut(FUND_AMOUNT / 8, USDT_LIQUIDITY, BTCB_LIQUIDITY);
        uint256 amountOutETH = router.getAmountOut(FUND_AMOUNT / 8, USDT_LIQUIDITY, ETH_LIQUIDITY);
        uint256 amountOutBNB = router.getAmountOut(FUND_AMOUNT / 8, USDT_LIQUIDITY, BNB_LIQUIDITY);
        for (uint256 i; i < users.length; ++i) {
            if (users[i] == msg.sender) {
                assert(
                    rewardToken.balanceOf(users[i])
                        >= deployerBalanceBefore + FUND_AMOUNT / 2 / users.length - ACCEPTED_PRECISION_LOSS
                );
            } else {
                assert(rewardToken.balanceOf(users[i]) >= FUND_AMOUNT / 2 / users.length - ACCEPTED_PRECISION_LOSS);
            }
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOutRayFi / users.length - ACCEPTED_PRECISION_LOSS
            );
            assert(btcb.balanceOf(users[i]) >= amountOutBTCB / users.length - ACCEPTED_PRECISION_LOSS);
            assert(eth.balanceOf(users[i]) >= amountOutETH / users.length - ACCEPTED_PRECISION_LOSS);
            assert(bnb.balanceOf(users[i]) >= amountOutBNB / users.length - ACCEPTED_PRECISION_LOSS);
        }
    }

    function testMixedDistributionMultipleVaultsStateful() public {
        new FundRayFi().fundRayFi(address(rayFi));
        new CreateRayFiLiquidityPool().createRayFiLiquidityPool(
            address(rayFi), address(rewardToken), address(router), true
        );
        new AddMockRayFiVaults().addMockRayFiVaults(
            address(rayFi), address(rewardToken), address(btcb), address(eth), address(bnb), address(router), true
        );
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);
        new PartiallyStakeRayFiUsersMultipleVaults().partiallyStakeRayFiUsersMultipleVaults(address(rayFi), vaultTokens);

        address[] memory users = rayFi.getShareholders();
        uint256[] memory stakedBalancesBefore = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            stakedBalancesBefore[i] = rayFi.getStakedBalanceOf(users[i]);
        }
        uint256 deployerBalanceBefore = rewardToken.balanceOf(msg.sender);

        vm.startPrank(msg.sender);
        rayFi.snapshot();
        for (uint256 i; i < MAX_ATTEMPTS; ++i) {
            if (rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 10}(GAS_FOR_REWARDS, 0, new address[](0))) {
                break;
            }
        }
        vm.stopPrank();

        uint256 amountOutRayFi = router.getAmountOut(FUND_AMOUNT / 8, INITIAL_REWARD_LIQUIDITY, INITIAL_RAYFI_LIQUIDITY);
        uint256 amountOutBTCB = router.getAmountOut(FUND_AMOUNT / 8, USDT_LIQUIDITY, BTCB_LIQUIDITY);
        uint256 amountOutETH = router.getAmountOut(FUND_AMOUNT / 8, USDT_LIQUIDITY, ETH_LIQUIDITY);
        uint256 amountOutBNB = router.getAmountOut(FUND_AMOUNT / 8, USDT_LIQUIDITY, BNB_LIQUIDITY);
        for (uint256 i; i < users.length; ++i) {
            if (users[i] == msg.sender) {
                assert(
                    rewardToken.balanceOf(users[i])
                        >= deployerBalanceBefore + FUND_AMOUNT / 2 / users.length - ACCEPTED_PRECISION_LOSS
                );
            } else {
                assert(rewardToken.balanceOf(users[i]) >= FUND_AMOUNT / 2 / users.length - ACCEPTED_PRECISION_LOSS);
            }
            assert(
                rayFi.getStakedBalanceOf(users[i])
                    >= stakedBalancesBefore[i] + amountOutRayFi / users.length - ACCEPTED_PRECISION_LOSS
            );
            assert(btcb.balanceOf(users[i]) >= amountOutBTCB / users.length - ACCEPTED_PRECISION_LOSS);
            assert(eth.balanceOf(users[i]) >= amountOutETH / users.length - ACCEPTED_PRECISION_LOSS);
            assert(bnb.balanceOf(users[i]) >= amountOutBNB / users.length - ACCEPTED_PRECISION_LOSS);
        }
    }

    function testMultipleDistributionsNoVaultsStateful() public {
        FundRayFi fundRayFi = new FundRayFi();
        new CreateRayFiLiquidityPool().createRayFiLiquidityPool(
            address(rayFi), address(rewardToken), address(router), true
        );
        new CreateRayFiUsers().createRayFiUsers(address(rayFi), true);

        address[] memory users = rayFi.getShareholders();
        uint256[USER_COUNT + 1] memory balancesBefore;
        for (uint256 i; i < 10; ++i) {
            fundRayFi.fundRayFi(address(rayFi));

            for (uint256 j; j < users.length; ++j) {
                balancesBefore[j] = rewardToken.balanceOf(users[j]);
            }

            vm.startPrank(msg.sender);
            rayFi.snapshot();
            for (uint256 j; j < MAX_ATTEMPTS; ++j) {
                if (rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 10}(GAS_FOR_REWARDS, 0, new address[](0))) {
                    break;
                }
            }
            vm.stopPrank();

            for (uint256 j; j < users.length; ++j) {
                assert(
                    rewardToken.balanceOf(users[j])
                        >= balancesBefore[j] + FUND_AMOUNT / users.length - ACCEPTED_PRECISION_LOSS
                );
            }
        }
    }
}
