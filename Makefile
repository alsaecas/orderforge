SHELL := /bin/bash

.PHONY: install fmt lint build test test-unit test-fuzz test-invariant coverage slither check ci clean

install:
	forge install foundry-rs/forge-std@v1.16.2 --no-git
	forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 --no-git

fmt:
	forge fmt --check

lint:
	forge lint

build:
	forge build --sizes

test:
	forge test -vvv

test-unit:
	forge test --match-path 'test/unit/**' -vvv

test-fuzz:
	forge test --match-path 'test/fuzz/**' -vvv

test-invariant:
	forge test --match-path 'test/invariant/**' -vvv

coverage:
	forge coverage --report summary

slither:
	slither . --config-file slither.config.json

check: fmt lint build test coverage slither

ci:
	FOUNDRY_PROFILE=ci $(MAKE) check

clean:
	forge clean
