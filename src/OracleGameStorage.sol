// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ISupraOraclePull} from "./interfaces/SupraOracle.sol";

library OracleGameStorage {
    struct Storage {
        ISupraOraclePull oracle;
        uint256 startTime;
        uint256[] allPairs;
        int256 currentPairIndex;
        uint256 pairDuration;
        uint256 guessWaitTime;
        mapping(address => uint256) userPoints;
        mapping(address => bool) userParticipated;
        mapping(uint256 => PairGuesses) priceGuesses;
    }

    struct PriceGuess {
        uint256 timestamp;
        uint256 price;
        address nextGuesser; // linked list
    }

    struct PairGuesses {
        address firstGuesser; // first guesser in the linked list
        address lastGuesser; // last guesser in the linked list
        mapping(address => PriceGuess) guesses;
        uint256 lastTimestamp;
    }

    struct UserGuess {
        uint256 pair;
        uint256 timestamp;
        uint256 price;
        bool rewarded;
    }

    function getStorage() internal pure returns (Storage storage s) {
        bytes32 position = keccak256("oracleGame.storage");
        assembly {
            s.slot := position
        }
    }
}
