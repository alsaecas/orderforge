// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Canonical EIP-712 limit order used by OrderForge.
/// @dev `nonce` identifies one logical order per maker. `salt` prevents accidental
///      hash reuse if an off-chain system regenerates an order before settlement.
struct Order {
    address maker;
    address allowedTaker;
    address sellToken;
    address buyToken;
    uint128 sellAmount;
    uint128 buyAmount;
    uint64 expiry;
    uint256 nonce;
    bytes32 salt;
}

/// @notice Portable ABI envelope that a relayer/solver can serialize off-chain.
struct ExecutionPayload {
    Order order;
    bytes signature;
    uint128 sellFillAmount;
}

/// @notice Example typed position used to demonstrate deterministic position IDs.
struct YieldPosition {
    address owner;
    address vault;
    address asset;
    uint128 shares;
    uint64 openedAt;
    uint256 nonce;
}
