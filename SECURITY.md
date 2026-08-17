# Security policy

OrderForge is **educational portfolio software**. It has not been audited and should not be used with meaningful funds.

## Reporting a vulnerability

Please use GitHub private security advisories rather than opening a public issue for suspected vulnerabilities. Include a minimal reproduction, affected commit, impact and any suggested mitigation.

## Security assumptions

- ERC-20 tokens are expected to have conventional balance/transfer semantics. Fee-on-transfer, rebasing and malicious callback-capable tokens are out of scope.
- Makers intentionally approve OrderForge to transfer the sell token. Takers intentionally approve the buy token.
- EIP-712 signatures authorize exactly the typed order under the current chain and verifying contract domain.
- Contract-wallet signatures rely on the ERC-1271 implementation returning a correct result.
- There is no owner, proxy, upgrade mechanism, protocol fee, emergency withdrawal or privileged settlement path.

## Defensive design

- EIP-712 domain separation and typed hashing.
- EOA and ERC-1271 verification through OpenZeppelin `SignatureChecker`.
- Per-order partial-fill accounting plus maker nonce binding.
- Explicit order cancellation and nonce invalidation.
- Checks-effects-interactions and `ReentrancyGuard` around settlement.
- `SafeERC20` for token transfers.
- Cumulative proportional rounding so partial fills sum to the exact full-order price, while zero-payment fills are rejected.
- No intended token custody by the settlement contract.
- Stateful invariant tests assert no overfill, token conservation and zero protocol custody.
