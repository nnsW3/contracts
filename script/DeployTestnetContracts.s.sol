// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {CheckIn} from "../src/CheckIn.sol";
import {DateTime} from "../src/DateTime.sol";
import {Faucet} from "../src/Faucet.sol";
import {OracleGame} from "../src/OracleGame.sol";
import {PlumeGoon} from "../src/PlumeGoon.sol";
import {Whitelist} from "../src/Whitelist.sol";

contract DeployScript is Script {
    address private constant P_ADDRESS = 0x9C43568e50CaDd2e78942C1d4C66dF3489f65D6a;
    address private constant ORACLE_ADDRESS = 0x6bf7b21145Cbd7BB0b9916E6eB24EDA8A675D7C0;
    address private constant FAUCET_ADMIN_ADDRESS = 0xb28f50F7b12f609ee2868B7e6aecB58E0a7BB936;

    string[] private tokenNames = ["ETH", "P"];
    address[] private tokenAddresses = [address(1), P_ADDRESS];
    uint256[] private pairs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];

    function run() external {
        vm.startBroadcast();

        DateTime dateTime = new DateTime();
        console.log("DateTime deployed to:", address(dateTime));

        CheckIn checkIn = new CheckIn();
        checkIn.initialize(msg.sender, address(dateTime), address(dateTime));
        console.log("CheckIn deployed to:", address(checkIn));

        Faucet faucet = new Faucet();
        faucet.initialize(
            msg.sender,
            address(checkIn),
            tokenNames,
            tokenAddresses
        );
        console.log("Faucet deployed to:", address(faucet));
        checkIn._adminSetFaucetContract(address(faucet));
        faucet.transferAdmin(FAUCET_ADMIN_ADDRESS);

        OracleGame oracleGame = new OracleGame();
        oracleGame.initialize(
            ORACLE_ADDRESS,
            pairs,
            1721088000,
            msg.sender
        );
        console.log("OracleGame deployed to:", address(oracleGame));

        Whitelist whitelist = new Whitelist();
        whitelist.initialize(msg.sender);
        console.log("Whitelist deployed to:", address(whitelist));

        PlumeGoon plumeGoon = new PlumeGoon();
        plumeGoon.initialize(
            msg.sender,
            "Plume Goon NFT",
            "GOON",
            address(whitelist),
            address(checkIn),
            msg.sender,
            msg.sender
        );
        console.log("PlumeGoon deployed to:", address(plumeGoon));

        vm.stopBroadcast();
    }
}
