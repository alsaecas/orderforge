# Static analysis

OrderForge runs Slither in CI and treats unexpected findings as build failures. Two detector classes are explicitly excluded because they flag intentional protocol mechanics rather than defects.

## `arbitrary-send-erc20`

`fillOrder` transfers the maker's sell token with `transferFrom(order.maker, taker, amount)`. This is the settlement primitive, not an arbitrary unauthenticated transfer: before the transfer, OrderForge verifies the EIP-712 digest against `order.maker`, checks expiry/taker restrictions, enforces nonce/cancellation state and bounds the cumulative fill. The maker must also have deliberately approved OrderForge.

## `timestamp`

`block.timestamp` is used only to enforce the maker-signed order expiry. Small miner/validator timestamp latitude cannot alter the signed exchange rate, recipient, token pair or fill limits; it only affects the exact boundary at which an order becomes expired.

These exclusions are narrow and documented. Other Slither findings continue to fail CI.
