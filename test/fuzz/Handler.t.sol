// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RayFi} from "../../src/RayFi.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract Handler is Test {
    RayFi rayFi;
    ERC20Mock rewardToken;
    IUniswapV2Router02 router;
    ERC20Mock btcb;
    ERC20Mock eth;
    ERC20Mock bnb;

    uint160 public constant MINIMUM_TOKEN_BALANCE_FOR_REWARDS = 1_000 ether;
    uint160 public constant INITIAL_USER_BALANCE = 10_000 ether;
    uint32 public constant GAS_FOR_REWARDS = 5_000_000;
    uint8 public constant MAX_ATTEMPTS = 10;
    uint8 public constant USER_COUNT = 100;

    address[USER_COUNT] public users;

    constructor(
        RayFi _rayFi,
        ERC20Mock _rewardToken,
        IUniswapV2Router02 _router,
        ERC20Mock _btcb,
        ERC20Mock _eth,
        ERC20Mock _bnb
    ) {
        rayFi = _rayFi;
        rewardToken = _rewardToken;
        router = _router;
        btcb = _btcb;
        eth = _eth;
        bnb = _bnb;

        address rayFiOwner = rayFi.owner();
        for (uint256 i; i < USER_COUNT; ++i) {
            address user = makeAddr(string(abi.encode("user", i)));
            uint256 initialBalance = getRandomNumber(MINIMUM_TOKEN_BALANCE_FOR_REWARDS, INITIAL_USER_BALANCE);
            uint256 stakedBalance = getRandomNumber(0, initialBalance);
            address vault = getRandomVault();
            vm.startPrank(rayFiOwner);
            rayFi.transfer(user, initialBalance);
            vm.stopPrank();
            vm.startPrank(user);
            rayFi.stake(vault, stakedBalance);
            vm.stopPrank();
        }
    }

    function transfer(address to) external {
        uint256 amount = getRandomNumber(1_000 ether, 100_000 ether);
        vm.startPrank(address(this));
        rayFi.transfer(msg.sender, amount);
        vm.stopPrank();

        vm.startPrank(msg.sender);
        rayFi.transfer(to, amount);
    }

    function stake() external {
        uint256 amount = getRandomNumber(1_000 ether, 100_000 ether);
        vm.startPrank(address(this));
        rayFi.transfer(msg.sender, amount);
        vm.stopPrank();

        vm.startPrank(msg.sender);
        rayFi.stake(getRandomVault(), amount);
    }

    function unstake() external {
        uint256 amount = getRandomNumber(1_000 ether, 100_000 ether);
        amount = bound(amount, 0, rayFi.getStakedBalanceOf(msg.sender));
        if (amount == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        rayFi.unstake(getRandomVault(), amount);
    }

    function buy() external {
        uint256 amountIn = getRandomNumber(10 ether, 10_000 ether);
        rewardToken.mint(msg.sender, amountIn);
        address[] memory path = new address[](2);
        path[0] = address(rewardToken);
        path[1] = address(rayFi);

        vm.startPrank(msg.sender);
        rewardToken.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, 0, path, msg.sender, block.timestamp);
    }

    function sell() external {
        uint256 amountIn = getRandomNumber(1_000 ether, 100_000 ether);
        vm.startPrank(address(this));
        rayFi.transfer(msg.sender, amountIn);
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(rayFi);
        path[1] = address(rewardToken);

        vm.startPrank(msg.sender);
        rayFi.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, 0, path, msg.sender, block.timestamp);
    }

    function distributeRewardsStateless() external {
        uint256 amount = getRandomNumber(5_000 ether, 50_000 ether);
        rewardToken.mint(address(rayFi), amount);
        vm.startPrank(rayFi.owner());
        rayFi.snapshot();
        rayFi.distributeRewardsStateless(0);
    }

    function distributeRewardsStateful() external {
        uint256 amount = getRandomNumber(5_000 ether, 50_000 ether);
        rewardToken.mint(address(rayFi), amount);
        vm.startPrank(rayFi.owner());
        rayFi.snapshot();
        for (uint256 i; i < MAX_ATTEMPTS; ++i) {
            if (rayFi.distributeRewardsStateful{gas: GAS_FOR_REWARDS * 2}(GAS_FOR_REWARDS, 0, new address[](0))) {
                break;
            }
        }
    }

    // Helper function to generate pseudo random numbers
    uint256 private counter = 0;

    function getRandomNumber(uint256 lowerLimit, uint256 upperLimit) internal returns (uint256) {
        counter++;
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(counter)));
        return lowerLimit + (randomNumber % (upperLimit - lowerLimit + 1));
    }

    function getRandomVault() internal returns (address) {
        uint256 randomNumber = getRandomNumber(0, 3);
        if (randomNumber == 0) {
            return address(rayFi);
        } else if (randomNumber == 1) {
            return address(btcb);
        } else if (randomNumber == 2) {
            return address(eth);
        } else {
            return address(bnb);
        }
    }

    // Excludes contract from coverage report
    function test() public {}
}
