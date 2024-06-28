// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {goonUSD} from "../src/goonUSD.sol";
import {P} from "../src/P.sol";
import {stRWA} from "../src/stRWA.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployScript is Script {
    address private constant ADMIN_ADDRESS = 0x91D8c1dC4eD9D34300e8351435A598798f958e4F;

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        address pProxy = Upgrades.deployUUPSProxy(
            "P.sol",
            abi.encodeCall(P.initialize, (msg.sender))
        );
        console.log("P deployed to:", pProxy);

        address goonUSDProxy = Upgrades.deployUUPSProxy(
            "goonUSD.sol",
            abi.encodeCall(goonUSD.initialize, (msg.sender))
        );
        console.log("goonUSD deployed to:", goonUSDProxy);

        address stRWAProxy = Upgrades.deployUUPSProxy(
            "stRWA.sol",
            abi.encodeCall(stRWA.initialize, (msg.sender))
        );
        console.log("stRWA deployed to:", stRWAProxy);

        vm.stopBroadcast();
    }
}
