// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {RWAFactory} from "../src/RWAFactory.sol";

contract DeployScript is Script {
    address private constant ADMIN_ADDRESS = 0xF5A6c4a29610722C84dC25222AF09FA81fAa4BDE;

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        Upgrades.upgradeProxy(0xbFf9dFbA4f2DADf5Ce2C22fEF3241Aa466A2B0f3, "RWAFactory.sol", "");

        vm.stopBroadcast();
    }
}
