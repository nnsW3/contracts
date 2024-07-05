// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {CheckIn} from "../src/CheckIn.sol";

contract DeployScript is Script {
    address private constant ADMIN_ADDRESS = 0xF5A6c4a29610722C84dC25222AF09FA81fAa4BDE;

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        Upgrades.upgradeProxy(
            0x8ab5808B9A470Bae488aBab33A358a7108A4871F,
            "CheckIn.sol",
            abi.encodeCall(CheckIn.reinitialize, (0x075e2D02EBcea5dbcE6b7C9F3D203613c0D5B33B, 0x075e2D02EBcea5dbcE6b7C9F3D203613c0D5B33B, 0x075e2D02EBcea5dbcE6b7C9F3D203613c0D5B33B))
        );

        vm.stopBroadcast();
    }
}
