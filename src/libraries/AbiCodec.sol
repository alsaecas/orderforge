// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOrderForge} from "../interfaces/IOrderForge.sol";
import {ExecutionPayload, Order} from "../types/OrderTypes.sol";

/// @notice ABI helpers used by relayers, tests and contract integrations.
library AbiCodec {
    function encodeOrder(Order memory order) internal pure returns (bytes memory) {
        return abi.encode(order);
    }

    function decodeOrder(bytes memory data) internal pure returns (Order memory) {
        return abi.decode(data, (Order));
    }

    function encodeExecution(ExecutionPayload memory payload) internal pure returns (bytes memory) {
        return abi.encode(payload);
    }

    function decodeExecution(bytes memory data) internal pure returns (ExecutionPayload memory) {
        return abi.decode(data, (ExecutionPayload));
    }

    /// @notice Produces strongly-typed calldata for IOrderForge.fillOrder.
    function encodeFillCall(
        Order memory order,
        bytes memory signature,
        uint128 sellFillAmount
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(IOrderForge.fillOrder, (order, signature, sellFillAmount));
    }
}
