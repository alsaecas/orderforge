// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {CodecHarness} from "../../src/CodecHarness.sol";
import {IOrderForge} from "../../src/interfaces/IOrderForge.sol";
import {OrderForge} from "../../src/OrderForge.sol";
import {ExecutionPayload, Order, YieldPosition} from "../../src/types/OrderTypes.sol";
import {Mock1271Wallet} from "../mocks/Mock1271Wallet.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract OrderForgeTest is Test {
    uint256 internal constant MAKER_PK = 0xA11CE;
    uint256 internal constant TAKER_PK = 0xB0B;
    uint256 internal constant OTHER_PK = 0xC0FFEE;

    OrderForge internal forge;
    CodecHarness internal codec;
    MockERC20 internal sellToken;
    MockERC20 internal buyToken;
    address internal maker;
    address internal taker;
    address internal other;

    function setUp() public {
        maker = vm.addr(MAKER_PK);
        taker = vm.addr(TAKER_PK);
        other = vm.addr(OTHER_PK);

        forge = new OrderForge();
        codec = new CodecHarness();
        sellToken = new MockERC20("Sell Token", "SELL");
        buyToken = new MockERC20("Buy Token", "BUY");

        sellToken.mint(maker, 1_000_000 ether);
        buyToken.mint(taker, 1_000_000 ether);

        vm.prank(maker);
        sellToken.approve(address(forge), type(uint256).max);
        vm.prank(taker);
        buyToken.approve(address(forge), type(uint256).max);
    }

    function test_fullFillSettlesExactBalancesAndClosesOrder() external {
        Order memory order = _order(100 ether, 250 ether, address(0), 1, keccak256("full"));
        bytes memory signature = _sign(order, MAKER_PK);
        bytes32 digest = forge.hashOrder(order);

        vm.prank(taker);
        uint256 buyPaid = forge.fillOrder(order, signature, order.sellAmount);

        assertEq(buyPaid, 250 ether);
        assertEq(sellToken.balanceOf(maker), 1_000_000 ether - 100 ether);
        assertEq(sellToken.balanceOf(taker), 100 ether);
        assertEq(buyToken.balanceOf(maker), 250 ether);
        assertEq(buyToken.balanceOf(taker), 1_000_000 ether - 250 ether);
        assertEq(forge.filledSellAmount(digest), 100 ether);
        assertTrue(forge.nonceInvalidated(maker, order.nonce));
        assertEq(uint8(forge.orderState(order)), uint8(IOrderForge.OrderState.Filled));
        assertEq(sellToken.balanceOf(address(forge)), 0);
        assertEq(buyToken.balanceOf(address(forge)), 0);
    }

    function test_partialFillsUseCumulativeRoundingAndFinishExactly() external {
        Order memory order = _order(3, 10, address(0), 2, keccak256("rounding"));
        bytes memory signature = _sign(order, MAKER_PK);

        vm.startPrank(taker);
        uint256 first = forge.fillOrder(order, signature, 1);
        uint256 second = forge.fillOrder(order, signature, 1);
        uint256 third = forge.fillOrder(order, signature, 1);
        vm.stopPrank();

        assertEq(first, 4);
        assertEq(second, 3);
        assertEq(third, 3);
        assertEq(first + second + third, order.buyAmount);
    }

    function test_partialFillThatWouldPayZeroBuyUnitsReverts() external {
        Order memory order = _order(10, 1, address(0), 14, keccak256("zero-buy-fill"));
        bytes memory signature = _sign(order, MAKER_PK);

        vm.prank(taker);
        assertEq(forge.fillOrder(order, signature, 1), 1);

        vm.expectRevert(OrderForge.ZeroBuyFill.selector);
        vm.prank(taker);
        forge.fillOrder(order, signature, 1);

        assertEq(forge.filledSellAmount(forge.hashOrder(order)), 1);
    }

    function test_restrictedTakerRejectsOtherCaller() external {
        Order memory order = _order(100 ether, 200 ether, taker, 3, keccak256("restricted"));
        bytes memory signature = _sign(order, MAKER_PK);

        vm.expectRevert(abi.encodeWithSelector(OrderForge.UnauthorizedTaker.selector, other, taker));
        vm.prank(other);
        forge.fillOrder(order, signature, 10 ether);
    }

    function test_expiredOrderCannotFill() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 4, keccak256("expired"));
        order.expiry = uint64(block.timestamp + 1);
        bytes memory signature = _sign(order, MAKER_PK);
        vm.warp(block.timestamp + 2);

        vm.expectRevert(abi.encodeWithSelector(OrderForge.OrderExpired.selector, order.expiry));
        vm.prank(taker);
        forge.fillOrder(order, signature, 10 ether);
    }

    function test_invalidSignatureCannotFill() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 5, keccak256("bad-sig"));
        bytes memory signature = _sign(order, OTHER_PK);

        vm.expectRevert(OrderForge.InvalidSignature.selector);
        vm.prank(taker);
        forge.fillOrder(order, signature, 10 ether);
    }

    function test_makerCanCancelRemainingOrder() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 6, keccak256("cancel"));
        bytes memory signature = _sign(order, MAKER_PK);

        vm.prank(taker);
        forge.fillOrder(order, signature, 25 ether);

        vm.prank(maker);
        forge.cancelOrder(order);

        assertEq(uint8(forge.orderState(order)), uint8(IOrderForge.OrderState.Cancelled));
        vm.expectRevert(abi.encodeWithSelector(OrderForge.OrderCancelled.selector, forge.hashOrder(order)));
        vm.prank(taker);
        forge.fillOrder(order, signature, 1 ether);
    }

    function test_nonceInvalidationCancelsAllOrdersUsingThatNonce() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 7, keccak256("nonce"));
        bytes memory signature = _sign(order, MAKER_PK);

        vm.prank(maker);
        forge.invalidateNonce(order.nonce);

        vm.expectRevert(abi.encodeWithSelector(OrderForge.NonceInvalidated.selector, maker, order.nonce));
        vm.prank(taker);
        forge.fillOrder(order, signature, 1 ether);
    }

    function test_nonceBindsToFirstPartiallyFilledOrder() external {
        Order memory firstOrder = _order(100 ether, 200 ether, address(0), 8, keccak256("first"));
        Order memory conflictingOrder = _order(100 ether, 300 ether, address(0), 8, keccak256("second"));
        bytes memory firstSig = _sign(firstOrder, MAKER_PK);
        bytes memory conflictSig = _sign(conflictingOrder, MAKER_PK);

        vm.prank(taker);
        forge.fillOrder(firstOrder, firstSig, 10 ether);

        bytes32 expectedHash = forge.hashOrder(firstOrder);
        bytes32 actualHash = forge.hashOrder(conflictingOrder);
        vm.expectRevert(
            abi.encodeWithSelector(OrderForge.NonceAlreadyBound.selector, 8, expectedHash, actualHash)
        );
        vm.prank(taker);
        forge.fillOrder(conflictingOrder, conflictSig, 10 ether);
    }

    function test_eip712DigestChangesAcrossVerifyingContracts() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 9, keccak256("domain"));
        OrderForge secondForge = new OrderForge();

        assertNotEq(forge.hashOrder(order), secondForge.hashOrder(order));
    }

    function test_erc1271ContractWalletSignatureIsSupported() external {
        uint256 walletOwnerPk = 0xD00D;
        address walletOwner = vm.addr(walletOwnerPk);
        Mock1271Wallet wallet = new Mock1271Wallet(walletOwner);
        sellToken.mint(address(wallet), 100 ether);

        vm.prank(walletOwner);
        wallet.approveToken(sellToken, address(forge), type(uint256).max);

        Order memory order = _order(100 ether, 200 ether, address(0), 10, keccak256("1271"));
        order.maker = address(wallet);
        bytes memory signature = _sign(order, walletOwnerPk);

        vm.prank(taker);
        forge.fillOrder(order, signature, 100 ether);

        assertEq(sellToken.balanceOf(taker), 100 ether);
        assertEq(buyToken.balanceOf(address(wallet)), 200 ether);
    }

    function test_standardAbiOrderRoundTrip() external view {
        Order memory original = _order(123, 456, taker, 11, keccak256("codec"));
        bytes memory encoded = codec.encodeOrder(original);
        Order memory decoded = codec.decodeOrder(encoded);

        assertEq(decoded.maker, original.maker);
        assertEq(decoded.allowedTaker, original.allowedTaker);
        assertEq(decoded.sellToken, original.sellToken);
        assertEq(decoded.buyToken, original.buyToken);
        assertEq(decoded.sellAmount, original.sellAmount);
        assertEq(decoded.buyAmount, original.buyAmount);
        assertEq(decoded.expiry, original.expiry);
        assertEq(decoded.nonce, original.nonce);
        assertEq(decoded.salt, original.salt);
    }

    function test_executionPayloadRoundTripIncludesDynamicSignature() external view {
        Order memory order = _order(100, 200, address(0), 12, keccak256("payload"));
        ExecutionPayload memory original = ExecutionPayload({
            order: order,
            signature: hex"010203040506",
            sellFillAmount: 25
        });

        bytes memory encoded = codec.encodeExecution(original);
        ExecutionPayload memory decoded = codec.decodeExecution(encoded);

        assertEq(decoded.signature, original.signature);
        assertEq(decoded.sellFillAmount, original.sellFillAmount);
        assertEq(decoded.order.salt, order.salt);
    }

    function test_encodeCallProducesTypedFillSelector() external view {
        Order memory order = _order(100, 200, address(0), 13, keccak256("call"));
        bytes memory callData = codec.encodeFillCall(order, hex"aabb", 50);
        bytes4 selector;
        assembly ("memory-safe") {
            selector := mload(add(callData, 0x20))
        }
        assertEq(selector, IOrderForge.fillOrder.selector);
    }

    function test_marketIdIsTokenOrderIndependentAndFeeSensitive() external view {
        address tokenA = address(0x1111);
        address tokenB = address(0x2222);
        assertEq(codec.marketId(tokenA, tokenB, 30), codec.marketId(tokenB, tokenA, 30));
        assertNotEq(codec.marketId(tokenA, tokenB, 30), codec.marketId(tokenA, tokenB, 100));
    }

    function test_dynamicPackedCollisionExistsButStandardAbiHashDoesNotCollide() external view {
        bytes32 packedLeft = keccak256(abi.encodePacked("a", "bc"));
        bytes32 packedRight = keccak256(abi.encodePacked("ab", "c"));
        assertEq(packedLeft, packedRight);

        assertNotEq(codec.hashDynamicPair("a", "bc"), codec.hashDynamicPair("ab", "c"));
    }

    function test_yieldPositionIdIsDeterministicAndNonceSensitive() external view {
        YieldPosition memory position = YieldPosition({
            owner: maker,
            vault: address(0x1234),
            asset: address(sellToken),
            shares: 99 ether,
            openedAt: 1_800_000_000,
            nonce: 1
        });

        bytes32 first = codec.yieldPositionId(position);
        assertEq(first, codec.yieldPositionId(position));
        position.nonce = 2;
        assertNotEq(first, codec.yieldPositionId(position));
    }

    function _order(
        uint128 sellAmount,
        uint128 buyAmount,
        address allowedTaker,
        uint256 nonce,
        bytes32 salt
    ) internal view returns (Order memory) {
        return Order({
            maker: maker,
            allowedTaker: allowedTaker,
            sellToken: address(sellToken),
            buyToken: address(buyToken),
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            expiry: uint64(block.timestamp + 1 days),
            nonce: nonce,
            salt: salt
        });
    }

    function _sign(Order memory order, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 digest = forge.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
