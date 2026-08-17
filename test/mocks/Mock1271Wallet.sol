// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Mock1271Wallet is IERC1271 {
    bytes4 private constant MAGIC_VALUE = IERC1271.isValidSignature.selector;

    address public immutable owner;

    error OnlyOwner();

    constructor(address owner_) {
        owner = owner_;
    }

    function approveToken(IERC20 token, address spender, uint256 amount) external {
        if (msg.sender != owner) revert OnlyOwner();
        token.approve(spender, amount);
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        return err == ECDSA.RecoverError.NoError && recovered == owner ? MAGIC_VALUE : bytes4(0xffffffff);
    }
}
