// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {RWAFactory} from "../src/RWAFactory.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {CheckIn} from "../src/CheckIn.sol";
import "../src/CheckInStorage.sol";

contract DeployScript is Script {
    address private constant ADMIN_ADDRESS = 0xF5A6c4a29610722C84dC25222AF09FA81fAa4BDE;
    address private constant CHECKIN_ADDRESS = 0x8ab5808B9A470Bae488aBab33A358a7108A4871F;

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        address launcherProxy = Upgrades.deployUUPSProxy(
            "RWAFactory.sol", abi.encodeCall(RWAFactory.initialize, (CHECKIN_ADDRESS))
        );
        console.log("Factory deployed to:", launcherProxy);

        CheckIn checkIn = CheckIn(CHECKIN_ADDRESS);
        checkIn._adminSetContract(CheckInStorage.Task.RWA_LAUNCHER, launcherProxy);

        vm.stopBroadcast();
    }
}
