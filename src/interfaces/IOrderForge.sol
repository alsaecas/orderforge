// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Order} from "../types/OrderTypes.sol";

interface IOrderForge {
    enum OrderState {
        Open,
        PartiallyFilled,
        Filled,
        Cancelled,
        Expired,
        NonceInvalidated
    }

    function fillOrder(
        Order calldata order,
        bytes calldata signature,
        uint128 sellFillAmount
    ) external returns (uint256 buyFillAmount);

    function cancelOrder(Order calldata order) external;

    function invalidateNonce(uint256 nonce) external;

    function hashOrder(Order calldata order) external view returns (bytes32 digest);

    function orderState(Order calldata order) external view returns (OrderState);
}
