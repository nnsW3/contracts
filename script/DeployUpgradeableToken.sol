// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {goonUSD} from "../src/goonUSD.sol";
import {GOON} from "../src/GOON.sol";
import {NEST} from "../src/NEST.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployScript is Script {
    address private constant ADMIN_ADDRESS = 0x91D8c1dC4eD9D34300e8351435A598798f958e4F;

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        address goonProxy = Upgrades.deployUUPSProxy("GOON.sol", abi.encodeCall(GOON.initialize, (msg.sender)));
        console.log("GOON deployed to:", goonProxy);

        address goonUSDProxy = Upgrades.deployUUPSProxy("goonUSD.sol", abi.encodeCall(goonUSD.initialize, (msg.sender)));
        console.log("goonUSD deployed to:", goonUSDProxy);

        address nestProxy = Upgrades.deployUUPSProxy("NEST.sol", abi.encodeCall(NEST.initialize, (msg.sender)));
        console.log("NEST deployed to:", nestProxy);

        vm.stopBroadcast();
    }
}
