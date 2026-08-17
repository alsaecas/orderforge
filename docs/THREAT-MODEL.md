# Threat model

## Assets

- maker authorization represented by an EIP-712 signature;
- maker sell-token allowance;
- taker buy-token allowance;
- order fill and cancellation state.

## Adversaries considered

### Signature replay
Mitigated by the EIP-712 chain/verifying-contract domain, per-order fill accounting, nonce binding, completion invalidation and explicit maker cancellation.

### Order mutation
Any changed typed field changes the signed digest and fails signature verification.

### Unauthorized taker
Restricted orders compare `allowedTaker` to `msg.sender` before state changes or transfers.

### Overfill / repeated fill
The contract records cumulative sell amount by order digest and reverts when a requested fill exceeds the exact remainder.

### Rounding extraction
Payment is calculated from the delta between cumulative floor-rounded obligations, preventing attackers from repeatedly exploiting independent per-fill rounding. A partial fill that would receive sell tokens while owing zero buy-token units is rejected; a larger fill can cross the next smallest-unit payment boundary.

### Reentrancy
Settlement is protected by `nonReentrant`, follows checks-effects-interactions and relies on atomic revert semantics if either transfer fails.

### Malicious relayer
Relayers have no privileged role. They cannot alter orders, bypass taker restrictions or transfer maker assets without a valid signature and allowance.

## Explicitly out of scope

- fee-on-transfer and rebasing tokens;
- intentionally malicious ERC-20 implementations;
- price discovery and oracle correctness;
- MEV protection and private order flow;
- solver competition and DEX routing;
- economic minimum-fill policies for very low-decimal assets;
- permit-based approvals;
- smart-wallet correctness beyond ERC-1271 validation semantics;
- upgradeability and governance (neither exists in this implementation).
