// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {CodecHarness} from "../../src/CodecHarness.sol";
import {OrderForge} from "../../src/OrderForge.sol";
import {Order} from "../../src/types/OrderTypes.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract OrderForgeFuzzTest is Test {
    uint256 internal constant MAKER_PK = 0xA11CE;
    address internal maker;
    address internal taker = address(0xB0B);
    OrderForge internal forge;
    CodecHarness internal codec;
    MockERC20 internal sellToken;
    MockERC20 internal buyToken;

    function setUp() public {
        maker = vm.addr(MAKER_PK);
        forge = new OrderForge();
        codec = new CodecHarness();
        sellToken = new MockERC20("Sell", "SELL");
        buyToken = new MockERC20("Buy", "BUY");

        sellToken.mint(maker, type(uint128).max);
        buyToken.mint(taker, type(uint128).max);
        vm.prank(maker);
        sellToken.approve(address(forge), type(uint256).max);
        vm.prank(taker);
        buyToken.approve(address(forge), type(uint256).max);
    }

    function testFuzz_partialFillNeverOverfillsAndBalancesMatch(
        uint128 rawSellAmount,
        uint128 rawBuyAmount,
        uint128 rawFill
    ) external {
        uint128 sellAmount = uint128(bound(rawSellAmount, 1, type(uint95).max));
        uint128 buyAmount = uint128(bound(rawBuyAmount, sellAmount, type(uint96).max));
        uint128 fillAmount = uint128(bound(rawFill, 1, sellAmount));

        Order memory order = _order(sellAmount, buyAmount, 1001);
        bytes memory signature = _sign(order);

        uint256 makerSellBefore = sellToken.balanceOf(maker);
        uint256 takerSellBefore = sellToken.balanceOf(taker);
        uint256 makerBuyBefore = buyToken.balanceOf(maker);
        uint256 takerBuyBefore = buyToken.balanceOf(taker);

        vm.prank(taker);
        uint256 buyPaid = forge.fillOrder(order, signature, fillAmount);

        assertLe(forge.filledSellAmount(forge.hashOrder(order)), sellAmount);
        assertEq(makerSellBefore - sellToken.balanceOf(maker), fillAmount);
        assertEq(sellToken.balanceOf(taker) - takerSellBefore, fillAmount);
        assertEq(buyToken.balanceOf(maker) - makerBuyBefore, buyPaid);
        assertEq(takerBuyBefore - buyToken.balanceOf(taker), buyPaid);
        assertGe(buyPaid, 1);
        assertLe(buyPaid, buyAmount);
    }

    function testFuzz_standardAbiRoundTripPreservesOrder(
        address allowedTaker,
        uint128 sellAmount,
        uint128 buyAmount,
        uint64 expiry,
        uint256 nonce,
        bytes32 salt
    ) external view {
        vm.assume(sellAmount != 0 && buyAmount != 0);
        Order memory order = Order({
            maker: maker,
            allowedTaker: allowedTaker,
            sellToken: address(sellToken),
            buyToken: address(buyToken),
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            expiry: expiry,
            nonce: nonce,
            salt: salt
        });

        Order memory decoded = codec.decodeOrder(codec.encodeOrder(order));
        assertEq(keccak256(abi.encode(decoded)), keccak256(abi.encode(order)));
    }

    function testFuzz_marketIdIsSymmetric(address tokenA, address tokenB, uint24 feeBps) external view {
        assertEq(codec.marketId(tokenA, tokenB, feeBps), codec.marketId(tokenB, tokenA, feeBps));
    }

    function _order(uint128 sellAmount, uint128 buyAmount, uint256 nonce) internal view returns (Order memory) {
        return Order({
            maker: maker,
            allowedTaker: address(0),
            sellToken: address(sellToken),
            buyToken: address(buyToken),
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            expiry: uint64(block.timestamp + 1 days),
            nonce: nonce,
            salt: keccak256(abi.encode(sellAmount, buyAmount, nonce))
        });
    }

    function _sign(Order memory order) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MAKER_PK, forge.hashOrder(order));
        return abi.encodePacked(r, s, v);
    }
}
