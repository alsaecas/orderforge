# ABI encoding and hashing decisions

This project is intentionally explicit about when to use standard ABI encoding, packed encoding and EIP-712 hashing.

## `abi.encode`

`Order`, `ExecutionPayload` and the dynamic-value hash helper use standard ABI encoding. Standard encoding preserves type boundaries and can be decoded with `abi.decode`.

```solidity
bytes memory wire = abi.encode(order);
Order memory decoded = abi.decode(wire, (Order));
```

The execution envelope includes a dynamic `bytes signature`, making standard encoding the natural portable representation for relayers.

## `abi.encodeCall`

`AbiCodec.encodeFillCall` creates strongly typed calldata for `IOrderForge.fillOrder`. The compiler checks the argument types against the target function signature.

## `abi.encodePacked`

Packed encoding is used only for a fixed-width market key:

```solidity
keccak256(abi.encodePacked(token0, token1, feeBps));
```

All fields are fixed-width, so their boundaries are unambiguous.

The unit suite also proves why concatenating multiple dynamic values is unsafe:

```solidity
keccak256(abi.encodePacked("a", "bc"))
    == keccak256(abi.encodePacked("ab", "c"));
```

The equivalent `keccak256(abi.encode(...))` hashes differ.

## EIP-712

Order signatures do not sign an ad-hoc packed blob. `OrderHash.structHash` hashes the typed fields with an explicit type hash, and `OrderForge` wraps that struct hash with OpenZeppelin `EIP712._hashTypedDataV4`.

The final digest therefore commits to:

- every order field;
- the `Order` type schema;
- protocol name and version;
- chain ID;
- verifying contract address.

A test deploys two OrderForge contracts and confirms the same order produces different final digests, demonstrating domain separation.
