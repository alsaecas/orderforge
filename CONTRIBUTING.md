# Contributing

This repository is primarily a portfolio/reference implementation, but focused improvements are welcome.

1. Open an issue for protocol-level behavior changes.
2. Keep settlement logic minimal and avoid adding privileged admin surfaces without a clear threat-model update.
3. Add unit tests for expected/revert paths, fuzz tests for input boundaries and invariant tests for stateful accounting changes.
4. Run `make check` before opening a pull request.
5. Update `docs/THREAT-MODEL.md` when assumptions or trust boundaries change.

Dependencies are installed with `make install`; generated Foundry output and dependency directories are intentionally not committed.
