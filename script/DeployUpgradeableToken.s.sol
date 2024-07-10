// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {goonUSD} from "../src/goonUSD.sol";
import {GOON} from "../src/GOON.sol";
import {NEST} from "../src/NEST.sol";
import {stRWA} from "../src/stRWA.sol";
import {NestStaking} from "../src/NestStaking.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployScript is Script {
    address private constant ADMIN_ADDRESS = 0x91D8c1dC4eD9D34300e8351435A598798f958e4F;
    address private constant DATETIME_ADDRESS = 0x118Bf897E75127dBbc7b59aB102B471F398EC300;
    address private constant CHECKIN_ADDRESS = 0x8Dc5b3f1CcC75604710d9F464e3C5D2dfCAb60d8;

    function run() external {
        vm.startBroadcast(ADMIN_ADDRESS);

        /*
        address goonProxy = Upgrades.deployUUPSProxy("GOON.sol", abi.encodeCall(GOON.initialize, (msg.sender)));
        console.log("GOON deployed to:", goonProxy);

        address goonUSDProxy = Upgrades.deployUUPSProxy("goonUSD.sol", abi.encodeCall(goonUSD.initialize, (msg.sender)));
        console.log("goonUSD deployed to:", goonUSDProxy);

        address nestProxy = Upgrades.deployUUPSProxy("NEST.sol", abi.encodeCall(NEST.initialize, (msg.sender)));
        console.log("NEST deployed to:", nestProxy);

        address goonProxy = 0xbA22114ec75f0D55C34A5E5A3cf384484Ad9e733;
        */
        address goonUSDProxy = 0x5c1409a46cD113b3A667Db6dF0a8D7bE37ed3BB3;
        address nestProxy = 0xd806259C3389Da7921316fb5489490EA5E2f88C6;

        address stRWAProxy = Upgrades.deployUUPSProxy("stRWA.sol", abi.encodeCall(stRWA.initialize, ("Plume Staked RWA Yield", "stRWA", msg.sender)));
        console.log("stRWA deployed to:", stRWAProxy);

        address nestStakingProxy = Upgrades.deployUUPSProxy("NestStaking.sol", abi.encodeCall(NestStaking.initialize, (stRWAProxy, goonUSDProxy, nestProxy, DATETIME_ADDRESS, CHECKIN_ADDRESS)));
        console.log("NestStaking deployed to:", nestStakingProxy);

        stRWA strwa = stRWA(stRWAProxy);
        strwa.setNestStaking(nestStakingProxy);

        vm.stopBroadcast();
    }
}
