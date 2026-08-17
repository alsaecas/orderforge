// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbiCodec} from "./libraries/AbiCodec.sol";
import {ProtocolIds} from "./libraries/ProtocolIds.sol";
import {ExecutionPayload, Order, YieldPosition} from "./types/OrderTypes.sol";

/// @notice Read-only harness exposing the portfolio's ABI and hashing primitives.
/// @dev Kept separate from settlement logic so educational helpers cannot expand
///      the trust surface of OrderForge itself.
contract CodecHarness {
    function encodeOrder(Order calldata order) external pure returns (bytes memory) {
        return AbiCodec.encodeOrder(order);
    }

    function decodeOrder(bytes calldata data) external pure returns (Order memory) {
        return AbiCodec.decodeOrder(data);
    }

    function encodeExecution(ExecutionPayload calldata payload) external pure returns (bytes memory) {
        return AbiCodec.encodeExecution(payload);
    }

    function decodeExecution(bytes calldata data) external pure returns (ExecutionPayload memory) {
        return AbiCodec.decodeExecution(data);
    }

    function encodeFillCall(Order calldata order, bytes calldata signature, uint128 sellFillAmount)
        external
        pure
        returns (bytes memory)
    {
        return AbiCodec.encodeFillCall(order, signature, sellFillAmount);
    }

    function marketId(address tokenA, address tokenB, uint24 feeBps) external pure returns (bytes32) {
        return ProtocolIds.marketId(tokenA, tokenB, feeBps);
    }

    function yieldPositionId(YieldPosition calldata position) external pure returns (bytes32) {
        return ProtocolIds.yieldPositionId(position);
    }

    function hashDynamicPair(string calldata left, string calldata right) external pure returns (bytes32) {
        return ProtocolIds.hashDynamicPair(left, right);
    }
}
