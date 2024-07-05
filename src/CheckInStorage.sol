// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

library CheckInStorage {
    enum Task {
        FLIGHT,
        FAUCET_ETH,
        FAUCET_GOON,
        FAUCET_USDC,
        NEST,
        RWA_LAUNCHER,
        AMBIENT,
        SUPRA,
        ASPECTA,
        DINARI,
        BUK,
        POLYTRADE,
        MIMO,
        PLURAL,
        LANDSHARE,
        MYSTIC_SWAP,
        RWAX,
        STRIKE,
        LANDX,
        ETHSIGN,
        SILVER_KOI
    }

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
        mapping(Task => uint256) taskPoints;
        mapping(Task => uint256) lastClaimed;
    }

    struct UserData {
        uint8 class;
        uint256 streakCount;
        uint256 reRolls;
        bool[7] weeklyCheckIns;
        uint256[] taskPoints;
        uint256[] lastClaimed;
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
        mapping(Task => uint256) taskBasePoints;
        mapping(Task => address) taskContractAddresses;
        mapping(Task => uint256) taskRefreshHours;
    }

    function getStorage() internal pure returns (Storage storage cs) {
        bytes32 position = keccak256("checkin.storage");
        assembly {
            cs.slot := position
        }
    }
}
