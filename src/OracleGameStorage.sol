// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ISupraOraclePull} from "./interfaces/SupraOracle.sol";
import {ICheckIn} from "./interfaces/ICheckIn.sol";

library OracleGameStorage {
    struct Storage {
        ISupraOraclePull oracle;
        ICheckIn checkin;
        uint256 startTime;
        uint256[] allPairs;
        int256 currentPairIndex;
        uint256 pairDuration;
        uint256 predictionWaitTime;
        uint256 predictionCooldown;
        mapping(uint256 => uint256) pairPrices;
        mapping(address => bool) userParticipated;
        mapping(uint256 => Predictions) predictions;
    }

    struct PriceMovement {
        uint256 timestamp;
        uint256 originalPrice;
        bool isLong;
        bool revealed;
        address next; // linked list
    }

    struct Predictions {
        address first; // first in the linked list
        address last; // last in the linked list
        mapping(address => PriceMovement) priceMovements;
        uint256 lastTimestamp;
    }

    struct UserPrediction {
        uint256 pair;
        uint256 timestamp;
        bool isLong;
        bool rewarded;
    }

    function getStorage() internal pure returns (Storage storage s) {
        bytes32 position = keccak256("oracleGame.storage");
        assembly {
            s.slot := position
        }
    }
}
