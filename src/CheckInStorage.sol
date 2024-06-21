// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

library CheckInStorage {
    struct UserInfo {
        uint8 class;
        uint16 lastCheckinYear;
        uint8 lastCheckinMonth;
        uint8 lastCheckinDay;
        uint8 lastCheckInWeek;
        uint256 streakCount;
        uint256 reRolls;
        uint256 flightPoints;
        uint256 faucetPoints;
        uint256 rwaStakingPoints;
        uint256 oracleGamePoints;
    }

    struct UserPoints {
        uint256 flightPoints;
        uint256 faucetPoints;
        uint256 rwaStakingPoints;
        uint256 oracleGamePoints;
    }

    struct Storage {
        uint256 basePoints;
        uint256 faucetPoints;
        address admin;
        address faucet;
        address goon;
        mapping(address => mapping(string => uint256)) faucetLastClaimed;
        mapping(address => UserInfo) users;
        mapping(address => bool[7]) weeklyCheckIns;
        address dateTimeAddress;
    }

    function getStorage() internal pure returns (Storage storage cs) {
        bytes32 position = keccak256("checkin.storage");
        assembly {
            cs.slot := position
        }
    }
}
