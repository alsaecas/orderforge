// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {OrderForge} from "../src/OrderForge.sol";

contract DeployOrderForge is Script {
    function run() external returns (OrderForge deployed) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        deployed = new OrderForge();
        vm.stopBroadcast();
    }
}
