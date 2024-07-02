// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IDateTime.sol";
import "./CheckInStorage.sol";

error NoReRollsLeft();
error InvalidClass();

contract CheckIn is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    using CheckInStorage for CheckInStorage.Storage;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 constant SECONDS_PER_DAY = 86400;

    event CheckInEvent(address indexed user, uint16 year, uint8 month, uint8 day);
    event PointsUpdated(address indexed user, CheckInStorage.UserPoints points);
    event TaskPointsUpdated(address indexed user, uint256[] taskPoints);

    function initialize(address _admin, address _dateTimeAddress, address _faucetAddress, address _swapAddress) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        cs.basePoints = 5000;
        cs.faucetPoints = 5000;
        cs.admin = _admin;
        cs.dateTimeAddress = _dateTimeAddress;
        cs.faucet = _faucetAddress;

        cs.taskBasePoints[CheckInStorage.Task.FAUCET_ETH] = 5000;
        cs.taskBasePoints[CheckInStorage.Task.FAUCET_P] = 5000;
        cs.taskBasePoints[CheckInStorage.Task.FAUCET_USDC] = 5000;
        cs.taskBasePoints[CheckInStorage.Task.AMBIENT] = 5000;

        cs.taskContractAddresses[CheckInStorage.Task.FAUCET_ETH] = _faucetAddress;
        cs.taskContractAddresses[CheckInStorage.Task.FAUCET_P] = _faucetAddress;
        cs.taskContractAddresses[CheckInStorage.Task.FAUCET_USDC] = _faucetAddress;
        cs.taskContractAddresses[CheckInStorage.Task.AMBIENT] = _swapAddress;

        _grantRole(ADMIN_ROLE, _admin);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    modifier _onlyFaucet() {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        require(msg.sender == cs.faucet, "Only faucet can call this function");
        _;
    }

    modifier _onlyGoon() {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        require(msg.sender == cs.goon, "Only goon contract can call this function");
        _;
    }

    function checkIn() public {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        CheckInStorage.UserInfo storage userInfo = cs.users[msg.sender];
        IDateTime dateTime = IDateTime(cs.dateTimeAddress);

        uint16 currentYear = dateTime.getYear(block.timestamp);
        uint8 currentMonth = dateTime.getMonth(block.timestamp);
        uint8 currentDay = dateTime.getDay(block.timestamp);
        uint8 currentWeekday = dateTime.getWeekday(block.timestamp);
        uint8 currentWeek = dateTime.getWeekNumber(block.timestamp);

        if (currentWeekday == 0) {
            currentWeekday = 7;
        }

        if (userInfo.lastCheckInWeek != currentWeek) {
            resetWeeklyCheckIns(msg.sender);
        }

        if (userInfo.streakCount == 0) {
            userInfo.streakCount = 1;
        } else {
            if (
                isNextDay(
                    userInfo.lastCheckinYear,
                    userInfo.lastCheckinMonth,
                    userInfo.lastCheckinDay,
                    currentYear,
                    currentMonth,
                    currentDay,
                    dateTime
                )
            ) {
                userInfo.streakCount++;
            } else if (
                !isSameDay(
                    userInfo.lastCheckinYear,
                    userInfo.lastCheckinMonth,
                    userInfo.lastCheckinDay,
                    currentYear,
                    currentMonth,
                    currentDay
                )
            ) {
                userInfo.streakCount = 1;
            }
        }

        userInfo.lastCheckinYear = currentYear;
        userInfo.lastCheckinMonth = currentMonth;
        userInfo.lastCheckinDay = currentDay;
        userInfo.reRolls += calculateReRolls(userInfo.class, userInfo.streakCount);
        cs.weeklyCheckIns[msg.sender][currentWeekday - 1] = true;
        userInfo.lastCheckInWeek = currentWeek;

        uint256 checkInIncrement = calculatePoints(userInfo.streakCount);
        userInfo.flightPoints += checkInIncrement;
        emit PointsUpdated(
            msg.sender,
            CheckInStorage.UserPoints(
                userInfo.flightPoints, userInfo.faucetPoints, userInfo.rwaStakingPoints, userInfo.oracleGamePoints
            )
        );

        emit CheckInEvent(msg.sender, currentYear, currentMonth, currentDay);

        userInfo.taskPoints[CheckInStorage.Task.CHECK_IN] += checkInIncrement;
        userInfo.lastClaimed[CheckInStorage.Task.CHECK_IN] = block.timestamp;
        uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;
        uint256[] memory taskPoints = new uint256[](tasksLength);
        for (uint256 i = 0; i < tasksLength; i++) {
            taskPoints[i] = userInfo.taskPoints[CheckInStorage.Task(i)];
        }
        emit TaskPointsUpdated(msg.sender, taskPoints);
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
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        uint256 multiplier = (streak - 1) * 5 + 10;
        return cs.basePoints * multiplier / 10;
    }

    function upgradeUserClass(address user, uint8 _class) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        if (cs.users[user].class == 3 || _class > 3 || _class < 0) revert InvalidClass();
        require(_class == cs.users[user].class + 1, "Can only upgrade to the next class");
        cs.users[user].class = _class;
        cs.users[user].flightPoints += 10000;
    }

    function _adminIncrementPoints(address user, uint256 points) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        cs.users[user].flightPoints += points;
    }

    function incrementPoints(address user, uint8 tier) public _onlyGoon {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        require(tier < 6, "Invalid tier");
        if (tier == 1) {
            cs.users[user].flightPoints += 8000;
        } else if (tier == 2) {
            cs.users[user].flightPoints += 10000;
        } else if (tier == 3) {
            cs.users[user].flightPoints += 12000;
        } else if (tier == 4) {
            cs.users[user].flightPoints += 18000;
        } else {
            cs.users[user].flightPoints += 30000;
        }
    }

    function incrementFaucetPoints(address user, string memory token) public _onlyFaucet {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        IDateTime dateTime = IDateTime(cs.dateTimeAddress);
        uint16 currentYear = dateTime.getYear(block.timestamp);
        uint8 currentMonth = dateTime.getMonth(block.timestamp);
        uint8 currentDay = dateTime.getDay(block.timestamp);

        uint16 prevYear = dateTime.getYear(cs.faucetLastClaimed[user][token]);
        uint8 prevMonth = dateTime.getMonth(cs.faucetLastClaimed[user][token]);
        uint8 prevDay = dateTime.getDay(cs.faucetLastClaimed[user][token]);

        if (!isSameDay(prevYear, prevMonth, prevDay, currentYear, currentMonth, currentDay)) {
            cs.faucetLastClaimed[user][token] = block.timestamp;
            cs.users[user].faucetPoints += cs.faucetPoints;
            emit PointsUpdated(
                user,
                CheckInStorage.UserPoints(
                    cs.users[user].flightPoints,
                    cs.users[user].faucetPoints,
                    cs.users[user].rwaStakingPoints,
                    cs.users[user].oracleGamePoints
                )
            );

            uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;
            uint256[] memory taskPoints = new uint256[](tasksLength);
            for (uint256 i = 0; i < tasksLength; i++) {
                taskPoints[i] = cs.users[user].taskPoints[CheckInStorage.Task(i)];
            }
            emit TaskPointsUpdated(user, taskPoints);
        }
    }

    function incrementTaskPoints(address user, CheckInStorage.Task task) public {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        require(msg.sender == cs.taskContractAddresses[task], "Only allowed smart contract can call this function");

        IDateTime dateTime = IDateTime(cs.dateTimeAddress);
        uint16 currentYear = dateTime.getYear(block.timestamp);
        uint8 currentMonth = dateTime.getMonth(block.timestamp);
        uint8 currentDay = dateTime.getDay(block.timestamp);

        uint256 lastClaimed = cs.users[user].lastClaimed[task];
        uint16 prevYear = dateTime.getYear(lastClaimed);
        uint8 prevMonth = dateTime.getMonth(lastClaimed);
        uint8 prevDay = dateTime.getDay(lastClaimed);

        if (!isSameDay(prevYear, prevMonth, prevDay, currentYear, currentMonth, currentDay)) {
            cs.users[user].lastClaimed[task] = block.timestamp;
            cs.users[user].taskPoints[task] += cs.taskBasePoints[task];

            uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;
            uint256[] memory taskPoints = new uint256[](tasksLength);
            for (uint256 i = 0; i < tasksLength; i++) {
                taskPoints[i] = cs.users[user].taskPoints[CheckInStorage.Task(i)];
            }
            emit TaskPointsUpdated(user, taskPoints);
        }
    }

    function _adminSetUserPoints(address user, CheckInStorage.UserPoints calldata points) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        CheckInStorage.UserInfo storage userInfo = cs.users[user];
        userInfo.flightPoints = points.flightPoints;
        userInfo.faucetPoints = points.faucetPoints;
        userInfo.rwaStakingPoints = points.rwaStakingPoints;
        userInfo.oracleGamePoints = points.oracleGamePoints;
    }
    
    function _adminSetUserTaskPoints(address user, uint256[] calldata taskPoints) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        CheckInStorage.UserInfo storage userInfo = cs.users[user];
        for (uint256 i = 0; i < taskPoints.length; i++) {
            userInfo.taskPoints[CheckInStorage.Task(i)] = taskPoints[i];
        }
    }

    function _adminSetUserClass(address user, uint8 _class) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        if (_class > 3 || _class < 0) revert InvalidClass();
        cs.users[user].class = _class;
    }

    function _adminUserReroll(address user, uint256 reroll) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        cs.users[user].reRolls = reroll;
    }

    function _setBasePoints(CheckInStorage.Task task, uint256 _basePoints) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        cs.taskBasePoints[task] = _basePoints;
    }

    function _decrementReRolls(address user) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        CheckInStorage.UserInfo storage userInfo = cs.users[user];
        if (userInfo.reRolls == 0) revert NoReRollsLeft();
        userInfo.reRolls--;
    }

    function _adminSetUserStreak(address user, uint256 streak) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        cs.users[user].streakCount = streak;
    }

    function _adminSetUserWeeklyCheckins(address user, bool[] calldata checkins) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        for (uint8 i = 0; i < 7; i++) {
            cs.weeklyCheckIns[user][i] = checkins[i];
        }
    }

    function _adminSetFaucetContract(address _faucet) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        cs.faucet = _faucet;
    }

    function _setGoonAddress(address _goon) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        cs.goon = _goon;
    }

    function _adminSetContract(CheckInStorage.Task task, address _contractAddress) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        cs.taskContractAddresses[task] = _contractAddress;
    }

    function isNextDay(
        uint16 lastYear,
        uint8 lastMonth,
        uint8 lastDay,
        uint16 currentYear,
        uint8 currentMonth,
        uint8 currentDay,
        IDateTime dateTime
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
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].streakCount;
    }

    function getPoints(address user) public view returns (CheckInStorage.UserPoints memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        CheckInStorage.UserInfo storage info = cs.users[user];
        return CheckInStorage.UserPoints(
            info.flightPoints, info.faucetPoints, info.rwaStakingPoints, info.oracleGamePoints
        );
    }

    function getUsersPoints(address[] memory _users) public view returns (CheckInStorage.UserPoints[] memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        CheckInStorage.UserPoints[] memory points = new CheckInStorage.UserPoints[](_users.length);

        for (uint256 i = 0; i < _users.length; i++) {
            CheckInStorage.UserInfo storage user = cs.users[_users[i]];
            points[i] = CheckInStorage.UserPoints(
                user.flightPoints, user.faucetPoints, user.rwaStakingPoints, user.oracleGamePoints
            );
        }
        return points;
    }

    function getTaskPoints(address user) public view returns (uint256[] memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;

        CheckInStorage.UserInfo storage userInfo = cs.users[user];
        uint256[] memory taskPoints = new uint256[](tasksLength);

        for (uint256 i = 0; i < tasksLength; i++) {
            taskPoints[i] = userInfo.taskPoints[CheckInStorage.Task(i)];
        }
        return taskPoints;
    }

    function getUsersTaskPoints(address[] memory _users) public view returns (uint256[][] memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;
        uint256[][] memory res = new uint256[][](_users.length);

        for (uint i = 0; i < _users.length; i++) {
            CheckInStorage.UserInfo storage userInfo = cs.users[_users[i]];
            uint256[] memory taskPoints = new uint256[](tasksLength);
            for (uint256 j = 0; j < tasksLength; j++) {
                taskPoints[j] = userInfo.taskPoints[CheckInStorage.Task(j)];
            }
            res[i] = taskPoints;
        }
        return res;
    }

    function getTaskLastClaimed(address user) public view returns (uint256[] memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;

        CheckInStorage.UserInfo storage userInfo = cs.users[user];
        uint256[] memory lastClaimed = new uint256[](tasksLength);
        for (uint256 i = 0; i < tasksLength; i++) {
            lastClaimed[i] = userInfo.lastClaimed[CheckInStorage.Task(i)];
        }
        return lastClaimed;
    }

    function getUsersTaskLastClaimed(address[] memory _users) public view returns (uint256[][] memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;
        uint256[][] memory res = new uint256[][](_users.length);

        for (uint i = 0; i < _users.length; i++) {
            CheckInStorage.UserInfo storage userInfo = cs.users[_users[i]];
            uint256[] memory lastClaimed = new uint256[](tasksLength);
            for (uint256 j = 0; j < tasksLength; j++) {
                lastClaimed[j] = userInfo.lastClaimed[CheckInStorage.Task(j)];
            }
            res[i] = lastClaimed;
        }
        return res;
    }

    function getWeeklyCheckIns(address user) public returns (bool[7] memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        IDateTime dateTime = IDateTime(cs.dateTimeAddress);
        uint8 currentWeek = dateTime.getWeekNumber(block.timestamp);

        if (cs.users[user].lastCheckInWeek != currentWeek) {
            return resetWeeklyCheckIns(user);
        }
        return cs.weeklyCheckIns[user];
    }

    function resetWeeklyCheckIns(address user) internal returns (bool[7] memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        for (uint8 i = 0; i < 7; i++) {
            cs.weeklyCheckIns[user][i] = false;
        }
        return cs.weeklyCheckIns[user];
    }

    // View functions for storage variables

    function getBasePoints() public view returns (uint256) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.basePoints;
    }

    function getFaucetPoints() public view returns (uint256) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.faucetPoints;
    }

    function getTaskBasePoints(CheckInStorage.Task task) public view returns (uint256) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.taskBasePoints[task];
    }

    function getAdmin() public view returns (address) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.admin;
    }

    function getFaucet() public view returns (address) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.faucet;
    }

    function getGoon() public view returns (address) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.goon;
    }

    function getContract(CheckInStorage.Task task) public view returns (address) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.taskContractAddresses[task];
    }
    
    function getDateTimeAddress() public view returns (address) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.dateTimeAddress;
    }

    function getFaucetLastClaimed(address user, string memory token) public view returns (uint256) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.faucetLastClaimed[user][token];
    }

    function getUserData(address user) public view returns (CheckInStorage.UserData memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        CheckInStorage.UserInfo storage userInfo = cs.users[user];

        uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;
        uint256[] memory taskPoints = new uint256[](tasksLength);
        uint256[] memory lastClaimed = new uint256[](tasksLength);
        for (uint256 i = 0; i < tasksLength; i++) {
            taskPoints[i] = userInfo.taskPoints[CheckInStorage.Task(i)];
            lastClaimed[i] = userInfo.lastClaimed[CheckInStorage.Task(i)];
        }

        return CheckInStorage.UserData(
            userInfo.class,
            userInfo.streakCount,
            userInfo.reRolls,
            cs.weeklyCheckIns[user],
            taskPoints,
            lastClaimed
        );
    }

    function getUserClass(address user) public view returns (uint8) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].class;
    }

    function getLastCheckinYear(address user) public view returns (uint16) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].lastCheckinYear;
    }

    function getLastCheckinMonth(address user) public view returns (uint8) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].lastCheckinMonth;
    }

    function getLastCheckinDay(address user) public view returns (uint8) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].lastCheckinDay;
    }

    function getLastCheckInWeek(address user) public view returns (uint8) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].lastCheckInWeek;
    }

    function getStreakCount(address user) public view returns (uint256) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].streakCount;
    }

    function getReRolls(address user) public view returns (uint256) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].reRolls;
    }

    function getFlightPoints(address user) public view returns (uint256) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].flightPoints;
    }

    function getFaucetPoints(address user) public view returns (uint256) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].faucetPoints;
    }

    function getRwaStakingPoints(address user) public view returns (uint256) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].rwaStakingPoints;
    }

    function getOracleGamePoints(address user) public view returns (uint256) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        return cs.users[user].oracleGamePoints;
    }
}
