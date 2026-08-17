# Security policy

OrderForge is **educational portfolio software**. It has not been audited and should not be used with meaningful funds.

## Supported versions

Security fixes are provided for the latest commit on `main`. No released version is currently supported because the project has not yet published a stable release. Historical commits and forks are outside the maintainer's support scope.

## Reporting a vulnerability

Please use [GitHub private security advisories](https://github.com/alsaecas/orderforge/security/advisories/new) rather than opening a public issue for suspected vulnerabilities. Do not disclose the issue publicly before a fix and coordinated disclosure timeline are agreed.

A useful report includes:

- the affected commit or version and execution path;
- a concise impact assessment and realistic attack prerequisites;
- a minimal Foundry reproduction or transaction sequence;
- relevant order fields, state transitions and token assumptions;
- a suggested mitigation, if available.

The maintainer will acknowledge the report, validate its scope and coordinate remediation and disclosure through the private advisory. No bug-bounty payment is promised.

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
- Cumulative floor rounding so accepted partial fills never transfer sell tokens for zero payment and the full order still settles to the exact signed price.
- No intended token custody by the settlement contract.
- Stateful invariant tests assert no overfill, token conservation and zero protocol custody.

Automated tests, coverage and static analysis are engineering controls, not substitutes for a professional audit. OrderForge has **not** undergone a professional smart-contract security audit.
