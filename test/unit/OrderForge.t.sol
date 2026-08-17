// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CodecHarness} from "../../src/CodecHarness.sol";
import {IOrderForge} from "../../src/interfaces/IOrderForge.sol";
import {OrderForge} from "../../src/OrderForge.sol";
import {ExecutionPayload, Order, YieldPosition} from "../../src/types/OrderTypes.sol";
import {Mock1271Wallet} from "../mocks/Mock1271Wallet.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockFalseReturnERC20} from "../mocks/MockFalseReturnERC20.sol";

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

        assertEq(first, 3);
        assertEq(second, 3);
        assertEq(third, 4);
        assertEq(first + second + third, order.buyAmount);
    }

    function test_partialFillBelowTokenResolutionRevertsButFullFillSucceeds() external {
        Order memory order = _order(10, 1, address(0), 14, keccak256("zero-buy-fill"));
        bytes memory signature = _sign(order, MAKER_PK);

        vm.expectRevert(OrderForge.ZeroBuyFill.selector);
        vm.prank(taker);
        forge.fillOrder(order, signature, 9);

        assertEq(forge.filledSellAmount(forge.hashOrder(order)), 0);

        vm.prank(taker);
        assertEq(forge.fillOrder(order, signature, 10), 1);
        assertEq(forge.filledSellAmount(forge.hashOrder(order)), 10);
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

    function test_malformedSignatureFailsSafely() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 28, keccak256("malformed-sig"));

        vm.expectRevert(OrderForge.InvalidSignature.selector);
        vm.prank(taker);
        forge.fillOrder(order, hex"deadbeef", 10 ether);
    }

    function test_mutatingSignedOrderInvalidatesSignature() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 29, keccak256("mutated-order"));
        bytes memory signature = _sign(order, MAKER_PK);
        order.buyAmount += 1;

        vm.expectRevert(OrderForge.InvalidSignature.selector);
        vm.prank(taker);
        forge.fillOrder(order, signature, 10 ether);
    }

    function test_signatureCannotReplayAcrossChainIds() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 30, keccak256("chain-domain"));
        bytes memory signature = _sign(order, MAKER_PK);
        vm.chainId(block.chainid + 1);

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
        vm.expectRevert(abi.encodeWithSelector(OrderForge.NonceAlreadyBound.selector, 8, expectedHash, actualHash));
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

    function test_erc1271WalletRejectsSignatureFromNonOwner() external {
        address walletOwner = vm.addr(0xD00D);
        Mock1271Wallet wallet = new Mock1271Wallet(walletOwner);

        Order memory order = _order(100 ether, 200 ether, address(0), 31, keccak256("1271-invalid"));
        order.maker = address(wallet);
        bytes memory signature = _sign(order, OTHER_PK);

        vm.expectRevert(OrderForge.InvalidSignature.selector);
        vm.prank(taker);
        forge.fillOrder(order, signature, 100 ether);
    }

    function test_falseReturningBuyTokenRevertsAndRollsBackFillState() external {
        MockFalseReturnERC20 falseToken = new MockFalseReturnERC20("False", "FALSE");
        falseToken.mint(taker, 200 ether);
        vm.prank(taker);
        falseToken.approve(address(forge), type(uint256).max);

        Order memory order = _order(100 ether, 200 ether, address(0), 32, keccak256("false-buy"));
        order.buyToken = address(falseToken);
        bytes memory signature = _sign(order, MAKER_PK);
        bytes32 digest = forge.hashOrder(order);

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        vm.prank(taker);
        forge.fillOrder(order, signature, order.sellAmount);

        assertEq(forge.filledSellAmount(digest), 0);
        assertFalse(forge.nonceInvalidated(maker, order.nonce));
        assertEq(forge.boundOrderHash(maker, order.nonce), bytes32(0));
    }

    function test_falseReturningSellTokenRevertsBothTransfersAtomically() external {
        MockFalseReturnERC20 falseToken = new MockFalseReturnERC20("False", "FALSE");
        falseToken.mint(maker, 100 ether);
        vm.prank(maker);
        falseToken.approve(address(forge), type(uint256).max);

        Order memory order = _order(100 ether, 200 ether, address(0), 33, keccak256("false-sell"));
        order.sellToken = address(falseToken);
        bytes memory signature = _sign(order, MAKER_PK);
        uint256 makerBuyBefore = buyToken.balanceOf(maker);
        uint256 takerBuyBefore = buyToken.balanceOf(taker);

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        vm.prank(taker);
        forge.fillOrder(order, signature, order.sellAmount);

        assertEq(buyToken.balanceOf(maker), makerBuyBefore);
        assertEq(buyToken.balanceOf(taker), takerBuyBefore);
        assertEq(forge.filledSellAmount(forge.hashOrder(order)), 0);
        assertFalse(forge.nonceInvalidated(maker, order.nonce));
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
        ExecutionPayload memory original =
            ExecutionPayload({order: order, signature: hex"010203040506", sellFillAmount: 25});

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

    function test_orderStateAndRemainingTrackLifecycle() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 15, keccak256("state"));
        bytes memory signature = _sign(order, MAKER_PK);

        assertEq(uint8(forge.orderState(order)), uint8(IOrderForge.OrderState.Open));
        assertEq(forge.remainingSellAmount(order), 100 ether);
        assertEq(forge.boundOrderHash(maker, order.nonce), bytes32(0));
        assertEq(forge.structHash(order), _structHashLocally(order));

        vm.prank(taker);
        forge.fillOrder(order, signature, 25 ether);

        bytes32 digest = forge.hashOrder(order);
        assertEq(uint8(forge.orderState(order)), uint8(IOrderForge.OrderState.PartiallyFilled));
        assertEq(forge.remainingSellAmount(order), 75 ether);
        assertEq(forge.boundOrderHash(maker, order.nonce), digest);
    }

    function test_orderStateReportsExpiredWithoutSettlement() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 16, keccak256("state-expired"));
        order.expiry = uint64(block.timestamp + 1);
        vm.warp(block.timestamp + 2);
        assertEq(uint8(forge.orderState(order)), uint8(IOrderForge.OrderState.Expired));
    }

    function test_orderStateReportsNonceInvalidated() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 17, keccak256("state-nonce"));
        vm.prank(maker);
        forge.invalidateNonce(order.nonce);
        assertEq(uint8(forge.orderState(order)), uint8(IOrderForge.OrderState.NonceInvalidated));
    }

    function test_nonMakerCannotCancelOrder() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 18, keccak256("not-maker"));
        vm.expectRevert(abi.encodeWithSelector(OrderForge.OnlyMaker.selector, taker, maker));
        vm.prank(taker);
        forge.cancelOrder(order);
    }

    function test_zeroMakerIsRejected() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 19, keccak256("zero-maker"));
        order.maker = address(0);
        vm.expectRevert(OrderForge.ZeroAddress.selector);
        vm.prank(taker);
        forge.fillOrder(order, hex"", 1 ether);
    }

    function test_zeroSellTokenIsRejected() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 20, keccak256("zero-sell"));
        order.sellToken = address(0);
        vm.expectRevert(OrderForge.ZeroAddress.selector);
        vm.prank(taker);
        forge.fillOrder(order, hex"", 1 ether);
    }

    function test_zeroBuyTokenIsRejected() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 21, keccak256("zero-buy"));
        order.buyToken = address(0);
        vm.expectRevert(OrderForge.ZeroAddress.selector);
        vm.prank(taker);
        forge.fillOrder(order, hex"", 1 ether);
    }

    function test_sameTokenIsRejected() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 22, keccak256("same-token"));
        order.buyToken = order.sellToken;
        vm.expectRevert(OrderForge.SameToken.selector);
        vm.prank(taker);
        forge.fillOrder(order, hex"", 1 ether);
    }

    function test_zeroSignedAmountsAreRejected() external {
        Order memory zeroSell = _order(0, 200 ether, address(0), 23, keccak256("zero-sell-amount"));
        vm.expectRevert(OrderForge.ZeroAmount.selector);
        vm.prank(taker);
        forge.fillOrder(zeroSell, hex"", 1);

        Order memory zeroBuy = _order(100 ether, 0, address(0), 24, keccak256("zero-buy-amount"));
        vm.expectRevert(OrderForge.ZeroAmount.selector);
        vm.prank(taker);
        forge.fillOrder(zeroBuy, hex"", 1);
    }

    function test_zeroFillIsRejected() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 25, keccak256("zero-fill"));
        bytes memory signature = _sign(order, MAKER_PK);
        vm.expectRevert(OrderForge.ZeroAmount.selector);
        vm.prank(taker);
        forge.fillOrder(order, signature, 0);
    }

    function test_fillCannotExceedRemainingAmount() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 26, keccak256("overfill"));
        bytes memory signature = _sign(order, MAKER_PK);

        vm.prank(taker);
        forge.fillOrder(order, signature, 60 ether);

        vm.expectRevert(abi.encodeWithSelector(OrderForge.FillExceedsRemaining.selector, 41 ether, 40 ether));
        vm.prank(taker);
        forge.fillOrder(order, signature, 41 ether);
    }

    function test_completedOrderHasNoRemainingSellAmount() external {
        Order memory order = _order(100 ether, 200 ether, address(0), 27, keccak256("no-remaining"));
        bytes memory signature = _sign(order, MAKER_PK);
        vm.prank(taker);
        forge.fillOrder(order, signature, order.sellAmount);
        assertEq(forge.remainingSellAmount(order), 0);
    }

    function _order(uint128 sellAmount, uint128 buyAmount, address allowedTaker, uint256 nonce, bytes32 salt)
        internal
        view
        returns (Order memory)
    {
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

    function _structHashLocally(Order memory order) internal pure returns (bytes32) {
        bytes32 typeHash = keccak256(
            "Order(address maker,address allowedTaker,address sellToken,address buyToken,uint128 sellAmount,uint128 buyAmount,uint64 expiry,uint256 nonce,bytes32 salt)"
        );
        return keccak256(
            abi.encode(
                typeHash,
                order.maker,
                order.allowedTaker,
                order.sellToken,
                order.buyToken,
                order.sellAmount,
                order.buyAmount,
                order.expiry,
                order.nonce,
                order.salt
            )
        );
    }

    function _sign(Order memory order, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 digest = forge.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
