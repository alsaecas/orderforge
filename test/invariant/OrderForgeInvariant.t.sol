// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {OrderForge} from "../../src/OrderForge.sol";
import {Order} from "../../src/types/OrderTypes.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract SettlementHandler is Test {
    OrderForge public immutable forge;
    MockERC20 public immutable sellToken;
    MockERC20 public immutable buyToken;
    address public immutable maker;
    address public immutable taker;
    Order internal _order;
    bytes internal _signature;

    uint256 public ghostSellFilled;
    uint256 public ghostBuyPaid;

    constructor(
        OrderForge forge_,
        MockERC20 sellToken_,
        MockERC20 buyToken_,
        address maker_,
        address taker_,
        Order memory order_,
        bytes memory signature_
    ) {
        forge = forge_;
        sellToken = sellToken_;
        buyToken = buyToken_;
        maker = maker_;
        taker = taker_;
        _order = order_;
        _signature = signature_;
    }

    function fill(uint256 rawAmount) external {
        bytes32 digest = forge.hashOrder(_order);
        uint256 filled = forge.filledSellAmount(digest);
        if (filled >= _order.sellAmount) return;
        if (forge.cancelled(digest) || forge.nonceInvalidated(maker, _order.nonce)) return;

        uint128 amount = uint128(bound(rawAmount, 1, uint256(_order.sellAmount) - filled));
        vm.prank(taker);
        uint256 buyPaid = forge.fillOrder(_order, _signature, amount);
        ghostSellFilled += amount;
        ghostBuyPaid += buyPaid;
    }

    function cancel() external {
        bytes32 digest = forge.hashOrder(_order);
        if (forge.cancelled(digest)) return;
        vm.prank(maker);
        forge.cancelOrder(_order);
    }

    function invalidateNonce() external {
        if (forge.nonceInvalidated(maker, _order.nonce)) return;
        vm.prank(maker);
        forge.invalidateNonce(_order.nonce);
    }

    function order() external view returns (Order memory) {
        return _order;
    }
}

contract OrderForgeInvariantTest is StdInvariant, Test {
    uint256 internal constant MAKER_PK = 0xA11CE;
    address internal maker;
    address internal taker = address(0xB0B);

    OrderForge internal forge;
    MockERC20 internal sellToken;
    MockERC20 internal buyToken;
    SettlementHandler internal handler;
    Order internal order;
    bytes32 internal digest;

    uint256 internal constant INITIAL_SELL = 1_000_000 ether;
    uint256 internal constant INITIAL_BUY = 2_000_000 ether;

    function setUp() public {
        maker = vm.addr(MAKER_PK);
        forge = new OrderForge();
        sellToken = new MockERC20("Sell", "SELL");
        buyToken = new MockERC20("Buy", "BUY");

        sellToken.mint(maker, INITIAL_SELL);
        buyToken.mint(taker, INITIAL_BUY);
        vm.prank(maker);
        sellToken.approve(address(forge), type(uint256).max);
        vm.prank(taker);
        buyToken.approve(address(forge), type(uint256).max);

        order = Order({
            maker: maker,
            allowedTaker: address(0),
            sellToken: address(sellToken),
            buyToken: address(buyToken),
            sellAmount: 10_000 ether,
            buyAmount: 23_333 ether,
            expiry: uint64(block.timestamp + 365 days),
            nonce: 777,
            salt: keccak256("invariant-order")
        });
        digest = forge.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MAKER_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        handler = new SettlementHandler(forge, sellToken, buyToken, maker, taker, order, signature);
        targetContract(address(handler));
    }

    function invariant_orderCanNeverBeOverfilled() external view {
        assertLe(forge.filledSellAmount(digest), order.sellAmount);
        assertEq(handler.ghostSellFilled(), forge.filledSellAmount(digest));
    }

    function invariant_tokenConservationAlwaysHolds() external view {
        assertEq(
            sellToken.balanceOf(maker) + sellToken.balanceOf(taker) + sellToken.balanceOf(address(forge)), INITIAL_SELL
        );
        assertEq(
            buyToken.balanceOf(maker) + buyToken.balanceOf(taker) + buyToken.balanceOf(address(forge)), INITIAL_BUY
        );
    }

    function invariant_settlementContractNeverCustodiesTokens() external view {
        assertEq(sellToken.balanceOf(address(forge)), 0);
        assertEq(buyToken.balanceOf(address(forge)), 0);
    }

    function invariant_cumulativePaymentNeverExceedsOrderPrice() external view {
        assertLe(handler.ghostBuyPaid(), order.buyAmount);
        if (forge.filledSellAmount(digest) == order.sellAmount) {
            assertEq(handler.ghostBuyPaid(), order.buyAmount);
        }
    }
}
