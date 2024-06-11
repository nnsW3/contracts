// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin-contracts/access/AccessControl.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "./interfaces/IDateTime.sol";

error NoReRollsLeft();
error InvalidClass();

contract CheckIn is AccessControl {
    struct UserInfo {
        // economy = 0, business = 1, first = 2, private = 3
        uint8 class;
        uint16 lastCheckinYear;
        uint8 lastCheckinMonth;
        uint8 lastCheckinDay;
        uint8 lastCheckInWeek;
        uint256 streakCount;
        uint256 reRolls;
        uint256 flightPoints; // checkin, mint, reroll, upgrade class
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

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 constant SECONDS_PER_DAY = 86400;

    uint256 public basePoints = 5000;
    uint256 public faucetPoints = 5000;
    address public admin;
    address public faucet;
    mapping(address => mapping(string => uint256)) public faucetLastClaimed;

    mapping(address => UserInfo) public users;
    mapping(address => bool[7]) public weeklyCheckIns;
    IDateTime dateTime;

    event CheckInEvent(address indexed user, uint16 year, uint8 month, uint8 day);
    event PointsUpdated(address indexed user, UserPoints points);

    constructor(address _dateTimeAddress, address _faucetAddress) {
        _grantRole(ADMIN_ROLE, msg.sender);
        dateTime = IDateTime(_dateTimeAddress);
        admin = msg.sender;
        faucet = _faucetAddress;
    }

    modifier _onlyFaucet() {
        require(msg.sender == faucet, "Only faucet can call this function");
        _;
    }

    modifier _onlyWithAdminSign(string memory _tokenUri, address user, bytes memory signature) {
        require(onlyWithAdminSign(_tokenUri, user, signature), "Invalid signature, cannot increment points");
        _;
    }

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function recoverSignerFromSignature(bytes32 message, bytes memory sig) internal pure returns (address) {
        require(sig.length == 65);

        uint8 v;
        bytes32 r;
        bytes32 s;

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        return ecrecover(message, v, r, s);
    }

    function onlyWithAdminSign(string memory _tokenUri, address user, bytes memory signature)
        internal
        view
        returns (bool)
    {
        bytes32 message = prefixed(keccak256(abi.encodePacked(_tokenUri, user)));
        return recoverSignerFromSignature(message, signature) == admin;
    }

    function checkIn() public {
        UserInfo storage user = users[msg.sender];
        uint16 currentYear = dateTime.getYear(block.timestamp);
        uint8 currentMonth = dateTime.getMonth(block.timestamp);
        uint8 currentDay = dateTime.getDay(block.timestamp);
        uint8 currentWeekday = dateTime.getWeekday(block.timestamp);
        uint8 currentWeek = dateTime.getWeekNumber(block.timestamp);

        // getWeekDay returns 0 for Sunday, we want start of week i.e 0 to be monday
        if (currentWeekday == 0) {
            currentWeekday = 7;
        }

        // Check if it's a new week and reset the weekly check-ins
        if (user.lastCheckInWeek != currentWeek) {
            resetWeeklyCheckIns(msg.sender);
        }

        if (user.streakCount == 0) {
            user.streakCount = 1; // First time checkin
        } else {
            if (
                isNextDay(
                    user.lastCheckinYear,
                    user.lastCheckinMonth,
                    user.lastCheckinDay,
                    currentYear,
                    currentMonth,
                    currentDay
                )
            ) {
                user.streakCount++;
            } else if (
                !isSameDay(
                    user.lastCheckinYear,
                    user.lastCheckinMonth,
                    user.lastCheckinDay,
                    currentYear,
                    currentMonth,
                    currentDay
                )
            ) {
                user.streakCount = 1;
            }
        }

        user.lastCheckinYear = currentYear;
        user.lastCheckinMonth = currentMonth;
        user.lastCheckinDay = currentDay;
        user.reRolls += calculateReRolls(user.class, user.streakCount);
        weeklyCheckIns[msg.sender][currentWeekday - 1] = true;
        user.lastCheckInWeek = currentWeek;

        user.flightPoints += calculatePoints(user.streakCount);
        emit PointsUpdated(
            msg.sender, UserPoints(user.flightPoints, user.faucetPoints, user.rwaStakingPoints, user.oracleGamePoints)
        );

        emit CheckInEvent(msg.sender, currentYear, currentMonth, currentDay);
    }

    // Class    | Rerolls
    // -------------------
    // Economy  | 1
    // Business | 2
    // First    | 3
    // Private  | 5
    function calculateReRolls(uint256 class, uint256 streak) private pure returns (uint256) {
        if (class > 3 || class < 0) revert InvalidClass();
        if (streak % 5 == 0 && streak != 0) {
            if (class == 3) {
                return class + 2;
            } else {
                return class + 1;
            }
        }
        return 0;
    }

    function calculatePoints(uint256 streak) private view returns (uint256) {
        uint256 multiplier = (streak - 1) * 5 + 10; // (n-1) * 0.5 + 1
        return basePoints * multiplier / 10;
    }

    function upgradeUserClass(address user, uint8 _class) public onlyRole(ADMIN_ROLE) {
        if (
            users[user].class == 3 // Should not upgrade if already private
                || _class > 3 || _class < 0
        ) revert InvalidClass();
        users[user].class = _class;
        require(_class > users[user].class, "Class not downgraded");
        users[user].flightPoints += 10000 * (_class - users[user].class);
    }

    function _adminIncrementPoints(address user, uint256 points) public onlyRole(ADMIN_ROLE) {
        users[user].flightPoints += points;
    }

    function incrementPoints(string memory _tokenUri, address user, bytes memory signature, uint8 tier)
        public
        _onlyWithAdminSign(_tokenUri, user, signature)
    {
        require(tier < 6, "Invalid tier");
        if (tier == 1) {
            users[user].flightPoints += 30000;
        } else if (tier == 2) {
            users[user].flightPoints += 18000;
        } else if (tier == 3) {
            users[user].flightPoints += 12000;
        } else if (tier == 4) {
            users[user].flightPoints += 10000;
        } else {
            users[user].flightPoints += 8000;
        }
    }

    function incrementFaucetPoints(address user, string memory token) public _onlyFaucet {
        uint16 currentYear = dateTime.getYear(block.timestamp);
        uint8 currentMonth = dateTime.getMonth(block.timestamp);
        uint8 currentDay = dateTime.getDay(block.timestamp);

        uint16 prevYear = dateTime.getYear(faucetLastClaimed[user][token]);
        uint8 prevMonth = dateTime.getMonth(faucetLastClaimed[user][token]);
        uint8 prevDay = dateTime.getDay(faucetLastClaimed[user][token]);

        if (!isSameDay(prevYear, prevMonth, prevDay, currentYear, currentMonth, currentDay)) {
            faucetLastClaimed[user][token] = block.timestamp;
            users[user].faucetPoints += faucetPoints;
            emit PointsUpdated(
                user,
                UserPoints(
                    users[user].flightPoints,
                    users[user].faucetPoints,
                    users[user].rwaStakingPoints,
                    users[user].oracleGamePoints
                )
            );
        }
    }

    function _adminSetUserPoints(address user, UserPoints calldata points) public onlyRole(ADMIN_ROLE) {
        UserInfo storage userInfo = users[user];
        userInfo.flightPoints = points.flightPoints;
        userInfo.faucetPoints = points.faucetPoints;
        userInfo.rwaStakingPoints = points.rwaStakingPoints;
        userInfo.oracleGamePoints = points.oracleGamePoints;
    }

    function _adminSetUserClass(address user, uint8 _class) public onlyRole(ADMIN_ROLE) {
        if (_class > 3 || _class < 0) revert InvalidClass();
        users[user].class = _class;
    }

    function _adminUserReroll(address user, uint256 reroll) public onlyRole(ADMIN_ROLE) {
        users[user].reRolls = reroll;
    }

    function _setBasePoints(uint256 _basePoints) public onlyRole(ADMIN_ROLE) {
        basePoints = _basePoints;
    }

    function _decrementReRolls(address user) public onlyRole(ADMIN_ROLE) {
        UserInfo storage userInfo = users[user];
        if (userInfo.reRolls == 0) revert NoReRollsLeft();
        userInfo.reRolls--;
    }

    function _adminSetUserStreak(address user, uint256 streak) public onlyRole(ADMIN_ROLE) {
        users[user].streakCount = streak;
    }

    // pass in all false to reset weekly checkins
    function _adminSetUserWeeklyCheckins(address user, bool[] calldata checkins) public onlyRole(ADMIN_ROLE) {
        for (uint8 i = 0; i < 7; i++) {
            weeklyCheckIns[user][i] = checkins[i];
        }
    }

    function isNextDay(
        uint16 lastYear,
        uint8 lastMonth,
        uint8 lastDay,
        uint16 currentYear,
        uint8 currentMonth,
        uint8 currentDay
    ) internal view returns (bool) {
        uint256 lastDateTimestamp = dateTime.toTimestamp(lastYear, lastMonth, lastDay);
        uint256 nextDayTimestamp = lastDateTimestamp + SECONDS_PER_DAY;

        uint16 nextDayYear = dateTime.getYear(nextDayTimestamp);
        uint8 nextDayMonth = dateTime.getMonth(nextDayTimestamp);
        uint8 nextDayDay = dateTime.getDay(nextDayTimestamp);

        return (nextDayYear == currentYear) && (nextDayMonth == currentMonth) && (nextDayDay == currentDay);
    }

    function isSameDay(
        uint16 lastYear,
        uint8 lastMonth,
        uint8 lastDay,
        uint16 currentYear,
        uint8 currentMonth,
        uint8 currentDay
    ) internal pure returns (bool) {
        return lastYear == currentYear && lastMonth == currentMonth && lastDay == currentDay;
    }

    function getStreak(address user) public view returns (uint256) {
        return users[user].streakCount;
    }

    function getReRolls(address user) public view returns (uint256) {
        return users[user].reRolls;
    }

    function getUserClass(address user) public view returns (uint256) {
        return users[user].class;
    }

    function getPoints(address user) public view returns (UserPoints memory) {
        UserInfo storage info = users[user];
        return UserPoints(info.flightPoints, info.faucetPoints, info.rwaStakingPoints, info.oracleGamePoints);
    }

    function getUsersPoints(address[] memory _users) public view returns (UserPoints[] memory) {
        UserPoints[] memory points = new UserPoints[](_users.length);
        for (uint256 i = 0; i < _users.length; i++) {
            UserInfo storage user = users[_users[i]];

            points[i] = UserPoints(user.flightPoints, user.faucetPoints, user.rwaStakingPoints, user.oracleGamePoints);
        }
        return points;
    }

    function getWeeklyCheckIns(address user) public returns (bool[7] memory) {
        uint8 currentWeek = dateTime.getWeekNumber(block.timestamp);
        if (users[user].lastCheckInWeek != currentWeek) {
            return resetWeeklyCheckIns(user);
        }
        return weeklyCheckIns[user];
    }

    function resetWeeklyCheckIns(address user) internal returns (bool[7] memory) {
        for (uint8 i = 0; i < 7; i++) {
            weeklyCheckIns[user][i] = false;
        }
        return weeklyCheckIns[user];
    }
}
