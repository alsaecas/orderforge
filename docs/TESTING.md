# Testing strategy

OrderForge uses complementary deterministic, fuzz and stateful invariant suites.

## Unit tests

The unit suite covers:

- exact full settlement and zero contract custody;
- cumulative floor rounding across partial fills, including minimum-resolution rejection;
- taker restrictions and expiry;
- invalid signatures;
- malformed, mutated and cross-chain-domain signatures;
- maker cancellation and nonce invalidation;
- first-fill nonce binding;
- EIP-712 verifying-contract domain separation;
- ERC-1271 contract-wallet signatures;
- ERC-1271 rejection and false-returning ERC-20 rollback behavior;
- `abi.encode` / `abi.decode` round trips;
- dynamic execution-payload encoding;
- `abi.encodeCall` selectors;
- deterministic market and yield-position IDs;
- a real `abi.encodePacked` dynamic collision and its safe `abi.encode` counterpart.

## Fuzz tests

Fuzz tests vary order sizes and fill sizes, then assert that balances and recorded fills agree. A two-partition property proves cumulative settlement reaches the exact signed buy amount across arbitrary valid ratios. Codec fuzzing checks round-trip preservation over arbitrary typed values. Market-ID fuzzing checks token-order symmetry.

## Stateful invariants

A handler randomly alternates between partial fills, order cancellation and nonce invalidation. It continues attempting fills after terminal state transitions and records any unexpected success. Across arbitrary call sequences the suite requires:

1. `filledSellAmount <= sellAmount`;
2. handler ghost accounting equals protocol accounting;
3. total sell-token and buy-token balances are conserved;
4. OrderForge never retains either settlement token;
5. cumulative payment never exceeds `buyAmount` and equals it on a full fill.
6. cancellation, nonce invalidation and completion permanently block further fills.

CI increases the fuzz and invariant run counts through the `ci` Foundry profile.

## Current verified baseline

The final hardening suite contains:

- 35 deterministic unit tests;
- 4 fuzz properties;
- 5 stateful invariants;
- 44 total Forge test functions.

With Solidity 0.8.30 and local Foundry 1.5.1, `forge coverage --report summary` reports:

| Scope | Lines | Statements | Branches | Functions |
| --- | ---: | ---: | ---: | ---: |
| Production contracts under `src/` | 100% (104/104) | 100% (127/127) | 100% (22/22) | 100% (27/27) |
| Repository aggregate | 94.23% (147/156) | 93.96% (171/182) | 86.21% (25/29) | 94.87% (37/39) |

The aggregate includes the unexecuted deployment script and partially instrumented invariant/mock helpers. It is not presented as production-contract coverage.
