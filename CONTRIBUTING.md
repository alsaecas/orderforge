# Contributing

This repository is primarily a portfolio/reference implementation, but focused improvements are welcome.

## Prerequisites and setup

- Git;
- Foundry 1.7.1 or a compatible newer stable release;
- Python and Slither 0.11.6 for the full static-analysis gate.

```bash
git clone https://github.com/alsaecas/orderforge.git
cd orderforge
make install
pipx install slither-analyzer==0.11.6
```

## Development checks

Run individual layers while iterating:

```bash
make fmt
make lint
make build
make test-unit
make test-fuzz
make test-invariant
make coverage
make slither
```

Before opening a pull request, run `make ci`. This uses the `ci` Foundry profile: 4,096 fuzz runs and 512 invariant runs at depth 128.

## Protocol and security expectations

1. Open an issue before changing signed fields, domain semantics, nonce/cancellation behavior, settlement arithmetic or trust assumptions.
2. Keep settlement minimal; do not add privileged admin, custody, fee, governance or upgrade surfaces without an explicit protocol-design decision.
3. Add focused unit regressions, property-oriented fuzz tests and stateful invariants appropriate to the change.
4. Preserve checks-effects-interactions, direct settlement and standard ERC-20 assumptions unless the threat model is deliberately revised.
5. Update `docs/THREAT-MODEL.md`, architecture and ABI documentation when behavior or assumptions change.

## Pull requests and commits

- Keep PRs reviewable and explain security implications, test results and coverage effects.
- Do not commit `lib/`, `out/`, `cache/`, broadcast artifacts, environment files, RPC URLs or private keys.
- Use concise Conventional Commit-style subjects where practical, such as `test:`, `fix:`, `docs:`, `ci:` or `chore:`.
- Ensure every required GitHub check is green and address review feedback before merge.

Dependencies are installed with `make install`; generated Foundry output and dependency directories are intentionally not committed.
