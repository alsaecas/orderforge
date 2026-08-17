// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IOrderForge} from "./interfaces/IOrderForge.sol";
import {OrderHash} from "./libraries/OrderHash.sol";
import {Order} from "./types/OrderTypes.sol";

/// @title OrderForge
/// @notice Non-custodial EIP-712 limit-order settlement with partial fills and replay protection.
/// @dev Portfolio/educational software. Not audited and not intended for production funds.
contract OrderForge is IOrderForge, EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error SameToken();
    error ZeroAmount();
    error OrderExpired(uint64 expiry);
    error UnauthorizedTaker(address caller, address allowedTaker);
    error InvalidSignature();
    error ZeroBuyFill();
    error OrderCancelled(bytes32 orderHash);
    error NonceInvalidated(address maker, uint256 nonce);
    error NonceAlreadyBound(uint256 nonce, bytes32 expectedOrderHash, bytes32 actualOrderHash);
    error FillExceedsRemaining(uint256 requested, uint256 remaining);
    error OnlyMaker(address caller, address maker);

    event OrderFilled(
        bytes32 indexed orderHash,
        address indexed maker,
        address indexed taker,
        uint256 sellFilled,
        uint256 buyPaid,
        uint256 cumulativeSellFilled
    );
    event OrderCompleted(bytes32 indexed orderHash, address indexed maker, uint256 nonce);
    event OrderCancelledByMaker(bytes32 indexed orderHash, address indexed maker, uint256 nonce);
    event NonceInvalidatedByMaker(address indexed maker, uint256 indexed nonce);
    event NonceBound(address indexed maker, uint256 indexed nonce, bytes32 indexed orderHash);

    mapping(bytes32 orderHash => uint128 amount) public filledSellAmount;
    mapping(bytes32 orderHash => bool isCancelled) public cancelled;
    mapping(address maker => mapping(uint256 nonce => bool isInvalidated)) public nonceInvalidated;
    mapping(address maker => mapping(uint256 nonce => bytes32 orderHash)) private _nonceBinding;

    constructor() EIP712("OrderForge", "1") {}

    function fillOrder(
        Order calldata order,
        bytes calldata signature,
        uint128 sellFillAmount
    ) external nonReentrant returns (uint256 buyFillAmount) {
        _validateOrderShape(order);

        if (order.expiry < block.timestamp) revert OrderExpired(order.expiry);
        if (order.allowedTaker != address(0) && order.allowedTaker != msg.sender) {
            revert UnauthorizedTaker(msg.sender, order.allowedTaker);
        }
        if (nonceInvalidated[order.maker][order.nonce]) {
            revert NonceInvalidated(order.maker, order.nonce);
        }

        bytes32 digest = _hashTypedDataV4(OrderHash.structHash(order));
        if (cancelled[digest]) revert OrderCancelled(digest);
        if (!SignatureChecker.isValidSignatureNow(order.maker, digest, signature)) {
            revert InvalidSignature();
        }

        _bindNonce(order.maker, order.nonce, digest);

        uint128 alreadyFilled = filledSellAmount[digest];
        uint256 remaining = uint256(order.sellAmount) - alreadyFilled;
        if (sellFillAmount == 0) revert ZeroAmount();
        if (sellFillAmount > remaining) revert FillExceedsRemaining(sellFillAmount, remaining);

        uint128 newFilled = alreadyFilled + sellFillAmount;

        // Cumulative rounding avoids per-fill drift: the final fill always totals exactly buyAmount.
        uint256 buyBefore = Math.mulDiv(
            alreadyFilled,
            order.buyAmount,
            order.sellAmount,
            Math.Rounding.Ceil
        );
        uint256 buyAfter = Math.mulDiv(
            newFilled,
            order.buyAmount,
            order.sellAmount,
            Math.Rounding.Ceil
        );
        buyFillAmount = buyAfter - buyBefore;
        if (buyFillAmount == 0) revert ZeroBuyFill();

        // Effects before interactions; any token failure reverts the state atomically.
        filledSellAmount[digest] = newFilled;
        if (newFilled == order.sellAmount) {
            nonceInvalidated[order.maker][order.nonce] = true;
        }

        IERC20(order.buyToken).safeTransferFrom(msg.sender, order.maker, buyFillAmount);
        IERC20(order.sellToken).safeTransferFrom(order.maker, msg.sender, sellFillAmount);

        emit OrderFilled(digest, order.maker, msg.sender, sellFillAmount, buyFillAmount, newFilled);
        if (newFilled == order.sellAmount) {
            emit OrderCompleted(digest, order.maker, order.nonce);
        }
    }

    function cancelOrder(Order calldata order) external {
        if (msg.sender != order.maker) revert OnlyMaker(msg.sender, order.maker);
        bytes32 digest = _hashTypedDataV4(OrderHash.structHash(order));
        cancelled[digest] = true;
        emit OrderCancelledByMaker(digest, order.maker, order.nonce);
    }

    function invalidateNonce(uint256 nonce) external {
        nonceInvalidated[msg.sender][nonce] = true;
        emit NonceInvalidatedByMaker(msg.sender, nonce);
    }

    function hashOrder(Order calldata order) external view returns (bytes32 digest) {
        return _hashTypedDataV4(OrderHash.structHash(order));
    }

    function structHash(Order calldata order) external pure returns (bytes32) {
        return OrderHash.structHash(order);
    }

    function boundOrderHash(address maker, uint256 nonce) external view returns (bytes32) {
        return _nonceBinding[maker][nonce];
    }

    function remainingSellAmount(Order calldata order) external view returns (uint256) {
        bytes32 digest = _hashTypedDataV4(OrderHash.structHash(order));
        uint128 filled = filledSellAmount[digest];
        if (filled >= order.sellAmount) return 0;
        return uint256(order.sellAmount) - filled;
    }

    function orderState(Order calldata order) external view returns (OrderState) {
        bytes32 digest = _hashTypedDataV4(OrderHash.structHash(order));
        uint128 filled = filledSellAmount[digest];

        if (filled >= order.sellAmount && order.sellAmount != 0) return OrderState.Filled;
        if (cancelled[digest]) return OrderState.Cancelled;
        if (nonceInvalidated[order.maker][order.nonce]) return OrderState.NonceInvalidated;
        if (order.expiry < block.timestamp) return OrderState.Expired;
        if (filled != 0) return OrderState.PartiallyFilled;
        return OrderState.Open;
    }

    function _validateOrderShape(Order calldata order) private pure {
        if (
            order.maker == address(0) || order.sellToken == address(0) || order.buyToken == address(0)
        ) revert ZeroAddress();
        if (order.sellToken == order.buyToken) revert SameToken();
        if (order.sellAmount == 0 || order.buyAmount == 0) revert ZeroAmount();
    }

    function _bindNonce(address maker, uint256 nonce, bytes32 digest) private {
        bytes32 bound = _nonceBinding[maker][nonce];
        if (bound == bytes32(0)) {
            _nonceBinding[maker][nonce] = digest;
            emit NonceBound(maker, nonce, digest);
            return;
        }
        if (bound != digest) revert NonceAlreadyBound(nonce, bound, digest);
    }
}
