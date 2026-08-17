# Learning evidence map

OrderForge is an original portfolio implementation created after studying ABI encoding, deterministic identifiers, positions, limit orders, hashing and advanced Foundry testing. It is not a copy of the course demonstration contract.

| Module concept | Evidence in OrderForge |
| --- | --- |
| `abi.encodePacked` | `ProtocolIds.marketId` uses packed encoding only with fixed-width fields |
| ABI encoding / decoding | `AbiCodec.encodeOrder/decodeOrder` and execution-envelope round trips |
| Function calldata | `AbiCodec.encodeFillCall` uses `abi.encodeCall` |
| Pool identifiers | token-order-independent `marketId(tokenA, tokenB, feeBps)` |
| Trading / position identifiers | EIP-712 order digest, nonce binding and typed yield-position ID |
| Swap / execution data | `ExecutionPayload` serializes order + dynamic signature + fill amount |
| Limit orders | complete signed-order settlement lifecycle |
| Yield positions | deterministic typed `YieldPosition` identifier |
| Hashing | EIP-712 struct hash, domain hash, standard-vs-packed collision tests |
| Position testing | fill state, cancellation, expiry and nonce lifecycle tests |
| Fuzz testing | arbitrary fill accounting and ABI round trips |
| Invariant testing | stateful overfill, conservation, custody and payment invariants |
| Extra / security testing | ERC-1271 signatures, cross-contract domain separation, unsafe packed collision proof |

## Improvements over the reference exercise

- actual decoding instead of encode-only examples;
- typed calldata generation rather than manual selector concatenation;
- EIP-712 instead of signing an ad-hoc packed payload;
- replay and nonce lifecycle modeled explicitly;
- partial-fill arithmetic with a stated invariant;
- EOA and contract-wallet signatures;
- stateful invariant testing, not only deterministic example assertions;
- security and architecture documentation tied to concrete trust boundaries.
