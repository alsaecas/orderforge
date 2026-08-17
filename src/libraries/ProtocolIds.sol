// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {YieldPosition} from "../types/OrderTypes.sol";

/// @notice Deterministic identifiers that demonstrate deliberate ABI encoding choices.
library ProtocolIds {
    bytes32 internal constant YIELD_POSITION_NAMESPACE = keccak256("ORDERFORGE_YIELD_POSITION_V1");

    /// @notice Creates an order-independent market identifier.
    /// @dev Packed encoding is safe here because every component is fixed-width.
    function marketId(address tokenA, address tokenB, uint24 feeBps) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1, feeBps));
    }

    /// @notice Creates a deterministic typed position ID using standard ABI encoding.
    function yieldPositionId(YieldPosition memory position) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                YIELD_POSITION_NAMESPACE,
                position.owner,
                position.vault,
                position.asset,
                position.shares,
                position.openedAt,
                position.nonce
            )
        );
    }

    /// @notice Safe hash for dynamic values; lengths/boundaries are preserved by abi.encode.
    function hashDynamicPair(string memory left, string memory right) internal pure returns (bytes32) {
        return keccak256(abi.encode(left, right));
    }
}
