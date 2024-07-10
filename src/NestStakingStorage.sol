// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ICheckIn} from "./interfaces/ICheckIn.sol";
import {IDateTime} from "./interfaces/IDateTime.sol";
import {stRWA} from "./stRWA.sol";
import {GOON} from "./GOON.sol";
import {NEST} from "./NEST.sol";
import {goonUSD} from "./goonUSD.sol";

library NestStakingStorage {
    struct Storage {
        stRWA stRwaToken;
        GOON goonToken;
        goonUSD goonUsdToken;
        NEST nestToken;
        address admin;
        uint256 APR;
        uint256 lastRebaseTimestamp;
        mapping(address => uint256) lastAccumulated;
        mapping(address => uint256) unclaimedRewards;
        IDateTime dateTime;
        ICheckIn checkIn;
    }

    function getStorage() internal pure returns (Storage storage rs) {
        bytes32 position = keccak256("neststaking.storage");
        assembly {
            rs.slot := position
        }
    }
}
