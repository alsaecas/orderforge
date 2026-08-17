// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Order} from "../types/OrderTypes.sol";

/// @notice EIP-712 struct hashing for OrderForge orders.
library OrderHash {
    bytes32 internal constant ORDER_TYPEHASH = keccak256(
        "Order(address maker,address allowedTaker,address sellToken,address buyToken,uint128 sellAmount,uint128 buyAmount,uint64 expiry,uint256 nonce,bytes32 salt)"
    );

    function structHash(Order memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
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
}
