# Testing strategy

OrderForge uses complementary deterministic, fuzz and stateful invariant suites.

## Unit tests

The unit suite covers:

- exact full settlement and zero contract custody;
- cumulative floor rounding across partial fills, including minimum-resolution rejection;
- taker restrictions and expiry;
- invalid signatures;
- maker cancellation and nonce invalidation;
- first-fill nonce binding;
- EIP-712 verifying-contract domain separation;
- ERC-1271 contract-wallet signatures;
- `abi.encode` / `abi.decode` round trips;
- dynamic execution-payload encoding;
- `abi.encodeCall` selectors;
- deterministic market and yield-position IDs;
- a real `abi.encodePacked` dynamic collision and its safe `abi.encode` counterpart.

## Fuzz tests

Fuzz tests vary order sizes and fill sizes, then assert that balances and recorded fills agree. Codec fuzzing checks round-trip preservation over arbitrary typed values. Market-ID fuzzing checks token-order symmetry.

## Stateful invariants

A handler randomly alternates between partial fills, order cancellation and nonce invalidation. Across arbitrary call sequences the suite requires:

1. `filledSellAmount <= sellAmount`;
2. handler ghost accounting equals protocol accounting;
3. total sell-token and buy-token balances are conserved;
4. OrderForge never retains either settlement token;
5. cumulative payment never exceeds `buyAmount` and equals it on a full fill.

CI increases the fuzz and invariant run counts through the `ci` Foundry profile.
