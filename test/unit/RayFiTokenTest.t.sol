// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployRayFiToken} from "../../script/DeployRayFiToken.s.sol";
import {RayFiToken, Ownable} from "../../src/RayFiToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract RayFiTokenTest is Test {
    RayFiToken rayFiToken;
    ERC20Mock dividendToken;
    IUniswapV2Router02 router;

    uint256 public constant DECIMALS = 18;
    uint256 public constant MAX_SUPPLY = 10_000_000 * (10 ** DECIMALS);
    uint256 public constant INITIAL_RAYFI_LIQUIDITY = 2_858_550 * (10 ** DECIMALS);
    uint256 public constant INITIAL_DIVIDEND_LIQUIDITY = 14_739 * (10 ** DECIMALS);
    uint256 public constant TRANSFER_AMOUNT = 10_000;
    uint256 public constant MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS = 1_000;
    uint8 public constant BUY_FEE = 4;
    uint8 public constant SELL_FEE = 4;

    string public constant TOKEN_NAME = "RayFi";
    string public constant TOKEN_SYMBOL = "RAYFI";

    address FEE_RECEIVER = makeAddr("feeReceiver");
    address DIVIDEND_RECEIVER = makeAddr("dividendReceiver");
    address DUMMY_ADDRESS = makeAddr("dummy");

    function setUp() external {
        DeployRayFiToken deployRayFiToken = new DeployRayFiToken();
        (rayFiToken, dividendToken, router) = deployRayFiToken.run(FEE_RECEIVER, DIVIDEND_RECEIVER);
    }

    modifier liquidityAdded() {
        vm.startPrank(msg.sender);
        dividendToken.mint(msg.sender, INITIAL_DIVIDEND_LIQUIDITY);

        rayFiToken.approve(address(router), INITIAL_RAYFI_LIQUIDITY);
        dividendToken.approve(address(router), INITIAL_DIVIDEND_LIQUIDITY);

        router.addLiquidity(
            address(rayFiToken),
            address(dividendToken),
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_DIVIDEND_LIQUIDITY,
            INITIAL_RAYFI_LIQUIDITY,
            INITIAL_DIVIDEND_LIQUIDITY,
            address(this),
            block.timestamp
        );

        rayFiToken.setAutomatedMarketPair(
            IUniswapV2Factory(router.factory()).getPair(address(rayFiToken), address(dividendToken)), true
        );
        vm.stopPrank();
        _;
    }

    modifier feesSet() {
        vm.startPrank(msg.sender);
        rayFiToken.setFeeAmounts(BUY_FEE, SELL_FEE);
        vm.stopPrank();
        _;
    }

    modifier minimumBalanceForDividendsSet() {
        vm.startPrank(msg.sender);
        rayFiToken.setMinimumTokenBalanceForDividends(MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS);
        vm.stopPrank();
        _;
    }

    /////////////////////////
    // Constructor Tests ////
    /////////////////////////

    function testRevertsOnZeroAddressArguments() public {
        vm.expectRevert(RayFiToken.RayFi__CannotSetToZeroAddress.selector);
        new RayFiToken(address(0), address(0), address(0), address(0));
    }

    function testERC20WasInitializedCorrectly() public view {
        assertEq(rayFiToken.name(), TOKEN_NAME);
        assertEq(rayFiToken.symbol(), TOKEN_SYMBOL);
        assertEq(rayFiToken.decimals(), DECIMALS);
        assertEq(rayFiToken.totalSupply(), MAX_SUPPLY);
    }

    function testRayFiWasInitializedCorrectly() public view {
        assertEq(address(rayFiToken.owner()), msg.sender);
        assertEq(rayFiToken.balanceOf(msg.sender), rayFiToken.totalSupply());
        assertEq(rayFiToken.getFeeReceiver(), FEE_RECEIVER);
    }

    //////////////////////
    // Transfer Tests ////
    //////////////////////

    function testTransferWorks() public {
        vm.startPrank(msg.sender);
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);
        vm.stopPrank();

        assertEq(rayFiToken.balanceOf(address(this)), TRANSFER_AMOUNT);
    }

    function testTransferFromWorks() public {
        vm.startPrank(msg.sender);
        rayFiToken.approve(address(this), TRANSFER_AMOUNT);
        vm.stopPrank();

        rayFiToken.transferFrom(msg.sender, address(this), TRANSFER_AMOUNT);
        assertEq(rayFiToken.balanceOf(address(this)), TRANSFER_AMOUNT);
    }

    function testTransfersUpdateShareholdersSet() public minimumBalanceForDividendsSet {
        // 1. Check new shareholders are added correctly and balances are updated
        vm.startPrank(msg.sender);
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);

        address[] memory shareholders = rayFiToken.getShareholders();
        assertEq(shareholders.length, 2);
        assertEq(shareholders[0], msg.sender);
        assertEq(shareholders[1], address(this));
        assertEq(rayFiToken.getSharesBalanceOf(msg.sender), MAX_SUPPLY - TRANSFER_AMOUNT);
        assertEq(rayFiToken.getSharesBalanceOf(address(this)), TRANSFER_AMOUNT);

        // 2. Check existing shareholders are updated correctly and balances are updated
        rayFiToken.transfer(address(this), TRANSFER_AMOUNT);

        shareholders = rayFiToken.getShareholders();
        assertEq(shareholders.length, 2);
        assertEq(shareholders[0], msg.sender);
        assertEq(shareholders[1], address(this));
        assertEq(rayFiToken.getSharesBalanceOf(msg.sender), MAX_SUPPLY - TRANSFER_AMOUNT * 2);
        assertEq(rayFiToken.getSharesBalanceOf(address(this)), TRANSFER_AMOUNT * 2);
        vm.stopPrank();

        // 3. Check existing shareholders are removed if their balance goes below the minimum
        rayFiToken.transfer(msg.sender, TRANSFER_AMOUNT * 2);

        shareholders = rayFiToken.getShareholders();
        assertEq(shareholders.length, 1);
        assertEq(shareholders[0], msg.sender);
        assertEq(rayFiToken.getSharesBalanceOf(msg.sender), MAX_SUPPLY);
        assertEq(rayFiToken.getSharesBalanceOf(address(this)), 0);
    }

    function testTransferRevertsWhenInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, TRANSFER_AMOUNT)
        );
        rayFiToken.transfer(DUMMY_ADDRESS, TRANSFER_AMOUNT);
    }

    function testTransferFromRevertsWhenInsufficientAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, TRANSFER_AMOUNT)
        );
        rayFiToken.transferFrom(msg.sender, DUMMY_ADDRESS, TRANSFER_AMOUNT);
    }

    function testTransferRevertsWhenInvalidSender() public {
        vm.startPrank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        rayFiToken.transfer(DUMMY_ADDRESS, TRANSFER_AMOUNT);
        vm.stopPrank();
    }

    function testTransferRevertsWhenInvalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        rayFiToken.transfer(address(0), TRANSFER_AMOUNT);
    }

    //////////////////
    // Swap Tests ////
    //////////////////

    function testSwapsWork() public liquidityAdded {
        // 1. Test buy swap
        address[] memory path = new address[](2);
        path[0] = address(rayFiToken);
        path[1] = address(dividendToken);
        uint256 amountIn = TRANSFER_AMOUNT * (10 ** DECIMALS);
        uint256 amountOut = router.getAmountOut(amountIn, INITIAL_RAYFI_LIQUIDITY, INITIAL_DIVIDEND_LIQUIDITY);
        vm.startPrank(msg.sender);
        rayFiToken.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut, path, msg.sender, block.timestamp
        );
        assertEq(dividendToken.balanceOf(msg.sender), amountOut);

        // 2. Test sell swap
        path[0] = address(dividendToken);
        path[1] = address(rayFiToken);
        amountIn = amountOut;
        (uint112 dividendLiquidity, uint112 rayFiLiquidity,) = IUniswapV2Pair(
            IUniswapV2Factory(router.factory()).getPair(address(rayFiToken), address(dividendToken))
        ).getReserves();
        amountOut = router.getAmountOut(amountIn, dividendLiquidity, rayFiLiquidity);
        dividendToken.approve(address(router), amountIn);
        uint256 rayFiBalanceBefore = rayFiToken.balanceOf(msg.sender);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut, path, msg.sender, block.timestamp
        );
        assertEq(rayFiToken.balanceOf(msg.sender), rayFiBalanceBefore + amountOut);
        vm.stopPrank();
    }

    function testSwapsTakeFees() public liquidityAdded feesSet {
        // 1. Test buy fee
        address[] memory path = new address[](2);
        path[0] = address(rayFiToken);
        path[1] = address(dividendToken);
        uint256 amountIn = TRANSFER_AMOUNT * (10 ** DECIMALS);
        uint256 feeAmount = amountIn * BUY_FEE / 100;
        uint256 adjustedAmountIn = amountIn - feeAmount;
        uint256 amountOut = router.getAmountOut(adjustedAmountIn, INITIAL_RAYFI_LIQUIDITY, INITIAL_DIVIDEND_LIQUIDITY);
        vm.startPrank(msg.sender);
        rayFiToken.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut, path, msg.sender, block.timestamp
        );
        assertEq(dividendToken.balanceOf(msg.sender), amountOut);
        assertEq(rayFiToken.balanceOf(FEE_RECEIVER), feeAmount);

        // 2. Test sell fee
        path[0] = address(dividendToken);
        path[1] = address(rayFiToken);
        amountIn = amountOut;
        (uint112 dividendLiquidity, uint112 rayFiLiquidity,) = IUniswapV2Pair(
            IUniswapV2Factory(router.factory()).getPair(address(rayFiToken), address(dividendToken))
        ).getReserves();
        amountOut = router.getAmountOut(amountIn, dividendLiquidity, rayFiLiquidity);
        feeAmount = amountOut * SELL_FEE / 100;
        uint256 adjustedAmountOut = amountOut - feeAmount;
        dividendToken.approve(address(router), amountIn);
        uint256 rayFiBalanceBefore = rayFiToken.balanceOf(msg.sender);
        uint256 feeReceiverRayFiBalanceBefore = rayFiToken.balanceOf(FEE_RECEIVER);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, adjustedAmountOut, path, msg.sender, block.timestamp
        );
        assertEq(rayFiToken.balanceOf(msg.sender), rayFiBalanceBefore + adjustedAmountOut);
        assertEq(rayFiToken.balanceOf(FEE_RECEIVER), feeReceiverRayFiBalanceBefore + feeAmount);
        vm.stopPrank();
    }

    ////////////////////
    // Setter Tests ////
    ////////////////////

    function testSetFeeAmounts() public {
        // Set valid fee amounts
        vm.startPrank(msg.sender);
        vm.recordLogs();
        rayFiToken.setFeeAmounts(BUY_FEE, SELL_FEE);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("FeeAmountsUpdated(uint8,uint8)"));
        (uint8 buyFee, uint8 sellFee) = abi.decode(entries[0].data, (uint8, uint8));
        assertEq(buyFee, BUY_FEE);
        assertEq(sellFee, SELL_FEE);
        assertEq(rayFiToken.getBuyFee(), BUY_FEE);
        assertEq(rayFiToken.getSellFee(), SELL_FEE);

        // Revert when total fee exceeds maximum
        buyFee = 99;
        sellFee = 99;
        vm.expectRevert(abi.encodeWithSelector(RayFiToken.RayFi__FeesTooHigh.selector, buyFee + sellFee));
        rayFiToken.setFeeAmounts(buyFee, sellFee);
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setFeeAmounts(BUY_FEE, SELL_FEE);
    }

    function testSetMinimumTokenBalanceForDividends() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        rayFiToken.setMinimumTokenBalanceForDividends(MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("MinimumTokenBalanceForDividendsUpdated(uint256,uint256)"));
        assertEq(entries[0].topics[1], bytes32(MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS));
        assertEq(entries[0].topics[2], bytes32(0));
        assertEq(rayFiToken.getMinimumTokenBalanceForDividends(), MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS);
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setMinimumTokenBalanceForDividends(MINIMUM_TOKEN_BALANCE_FOR_DIVIDENDS);
    }

    function testSetDividendToken() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newDividendToken = address(DUMMY_ADDRESS);
        rayFiToken.setDividendToken(newDividendToken);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("DividendTokenUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newDividendToken))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(address(dividendToken)))));
        assertEq(rayFiToken.getDividendToken(), newDividendToken);

        // Revert when zero address is passed as input
        vm.expectRevert(RayFiToken.RayFi__CannotSetToZeroAddress.selector);
        rayFiToken.setDividendToken(address(0));
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setDividendToken(newDividendToken);
    }

    function testSetRouter() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newRouter = address(DUMMY_ADDRESS);
        rayFiToken.setRouter(newRouter);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("RouterUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newRouter))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(address(router)))));

        // Revert when zero address is passed as input
        vm.expectRevert(RayFiToken.RayFi__CannotSetToZeroAddress.selector);
        rayFiToken.setRouter(address(0));
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setRouter(newRouter);
    }

    function testSetFeeReceiver() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newFeeReceiver = address(DUMMY_ADDRESS);
        rayFiToken.setFeeReceiver(newFeeReceiver);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("FeeReceiverUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newFeeReceiver))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(FEE_RECEIVER))));
        assertEq(rayFiToken.getFeeReceiver(), newFeeReceiver);

        // Revert when zero address is passed as input
        vm.expectRevert(RayFiToken.RayFi__CannotSetToZeroAddress.selector);
        rayFiToken.setFeeReceiver(address(0));
        vm.stopPrank();

        // Revert when called by non-msg.sender
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setFeeReceiver(newFeeReceiver);
    }

    function testSetDividendReceiver() public {
        // Test valid call
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address newDividendReceiver = address(DUMMY_ADDRESS);
        rayFiToken.setDividendReceiver(newDividendReceiver);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[0].topics[0], keccak256("DividendReceiverUpdated(address,address)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(newDividendReceiver))));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(DIVIDEND_RECEIVER))));

        // Revert when zero address is passed as input
        vm.expectRevert(RayFiToken.RayFi__CannotSetToZeroAddress.selector);
        rayFiToken.setDividendReceiver(address(0));
        vm.stopPrank();

        // Revert when called by non-owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rayFiToken.setDividendReceiver(newDividendReceiver);
    }
}
