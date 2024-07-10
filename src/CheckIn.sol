// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IDateTime.sol";
import "./CheckInStorage.sol";

error NoReRollsLeft();
error InvalidClass();
error CheckedInMoreThanOnce();

contract CheckIn is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    using CheckInStorage for CheckInStorage.Storage;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 constant SECONDS_PER_DAY = 86400;

    event CheckInEvent(address indexed user, uint16 year, uint8 month, uint8 day);
    event PointsUpdated(address indexed user, CheckInStorage.UserPoints points);
    event TaskPointsUpdated(address indexed user, uint256[] taskPoints);

    function initialize(address _admin, address _dateTimeAddress, address _faucetAddress) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        cs.basePoints = 5000;
        cs.faucetPoints = 5000;
        cs.admin = _admin;
        cs.dateTimeAddress = _dateTimeAddress;
        cs.faucet = _faucetAddress;

        _grantRole(ADMIN_ROLE, _admin);
    }

    function reinitialize(address _faucetAddress, address _stakingAddress, address _swapAddress)
        public
        reinitializer(2)
    {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();

        cs.taskBasePoints[CheckInStorage.Task.FAUCET_ETH] = 5000;
        cs.taskBasePoints[CheckInStorage.Task.FAUCET_GOON] = 5000;
        cs.taskBasePoints[CheckInStorage.Task.FAUCET_USDC] = 5000;
        cs.taskBasePoints[CheckInStorage.Task.NEST] = 5000;
        cs.taskBasePoints[CheckInStorage.Task.AMBIENT] = 5000;
        cs.taskBasePoints[CheckInStorage.Task.SUPRA] = 5000;

        cs.taskContractAddresses[CheckInStorage.Task.FAUCET_ETH] = _faucetAddress;
        cs.taskContractAddresses[CheckInStorage.Task.FAUCET_GOON] = _faucetAddress;
        cs.taskContractAddresses[CheckInStorage.Task.FAUCET_USDC] = _faucetAddress;
        cs.taskContractAddresses[CheckInStorage.Task.NEST] = _stakingAddress;
        cs.taskContractAddresses[CheckInStorage.Task.AMBIENT] = _swapAddress;

        cs.taskRefreshHours[CheckInStorage.Task.FAUCET_ETH] = 24;
        cs.taskRefreshHours[CheckInStorage.Task.FAUCET_GOON] = 24;
        cs.taskRefreshHours[CheckInStorage.Task.FAUCET_USDC] = 24;
        cs.taskRefreshHours[CheckInStorage.Task.NEST] = 0;
        cs.taskRefreshHours[CheckInStorage.Task.AMBIENT] = 24;
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

        uint256 streakCount = userInfo.streakCount;
        if (streakCount == 0) {
            streakCount = 1;
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
                streakCount++;
            } else if (
                isSameDay(
                    userInfo.lastCheckinYear,
                    userInfo.lastCheckinMonth,
                    userInfo.lastCheckinDay,
                    currentYear,
                    currentMonth,
                    currentDay
                )
            ) {
                revert CheckedInMoreThanOnce();
            } else {
                streakCount = 1;
            }
        }

        _setTaskPoints(msg.sender);

        userInfo.streakCount = streakCount;
        userInfo.lastCheckinYear = currentYear;
        userInfo.lastCheckinMonth = currentMonth;
        userInfo.lastCheckinDay = currentDay;
        userInfo.lastCheckInWeek = currentWeek;
        userInfo.reRolls += calculateReRolls(userInfo.class, streakCount);
        cs.weeklyCheckIns[msg.sender][currentWeekday - 1] = true;

        uint256 checkInIncrement = calculatePoints(streakCount);
        userInfo.flightPoints += checkInIncrement;
        emit PointsUpdated(
            msg.sender,
            CheckInStorage.UserPoints(
                userInfo.flightPoints, userInfo.faucetPoints, userInfo.rwaStakingPoints, userInfo.oracleGamePoints
            )
        );

        emit CheckInEvent(msg.sender, currentYear, currentMonth, currentDay);

        _incrementTaskPoints(msg.sender, CheckInStorage.Task.FLIGHT, checkInIncrement);
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
        CheckInStorage.UserInfo storage userInfo = cs.users[user];

        _setTaskPoints(user);

        if (_class != userInfo.class + 1 || _class > 3) revert InvalidClass();
        userInfo.class = _class;
        userInfo.flightPoints += 10000;

        _incrementTaskPoints(user, CheckInStorage.Task.FLIGHT, 10000);
    }

    function _adminIncrementPoints(address user, uint256 points) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();

        _setTaskPoints(user);
        cs.users[user].flightPoints += points;
        _incrementTaskPoints(user, CheckInStorage.Task.FLIGHT, points);
    }

    function incrementPoints(address user, uint8 tier) public _onlyGoon {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        uint256 amount = 0;

        require(tier < 6, "Invalid tier");
        if (tier == 1) {
            amount = 8000;
        } else if (tier == 2) {
            amount = 10000;
        } else if (tier == 3) {
            amount = 12000;
        } else if (tier == 4) {
            amount = 18000;
        } else {
            amount = 30000;
        }

        _setTaskPoints(user);
        cs.users[user].flightPoints += amount;
        _incrementTaskPoints(user, CheckInStorage.Task.FLIGHT, amount);
    }

    function incrementFaucetPoints(address user, string memory token) public _onlyFaucet {
        _setTaskPoints(user);

        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();

        IDateTime dateTime = IDateTime(cs.dateTimeAddress);
        uint8 currentDay = dateTime.getDay(block.timestamp);
        uint8 prevDay = dateTime.getDay(cs.faucetLastClaimed[user][token]);

        if (currentDay == prevDay) {
            return;
        }

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

        _incrementTaskPoints(user, CheckInStorage.Task.FAUCET_ETH, cs.taskBasePoints[CheckInStorage.Task.FAUCET_ETH]);
    }

    function incrementTaskPoints(address user, CheckInStorage.Task task) public {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();

        require(msg.sender == cs.taskContractAddresses[task], "Only allowed smart contract can call this function");

        uint256 refreshHours = cs.taskRefreshHours[task];
        uint256 lastClaimed = cs.users[user].lastClaimed[task];

        if (refreshHours == 0 && lastClaimed == 0) {
            _incrementTaskPoints(user, task, cs.taskBasePoints[task]);
            return;
        }

        IDateTime dateTime = IDateTime(cs.dateTimeAddress);
        uint16 currentYear = dateTime.getYear(block.timestamp);
        uint8 currentMonth = dateTime.getMonth(block.timestamp);
        uint8 currentDay = dateTime.getDay(block.timestamp);

        uint16 prevYear = dateTime.getYear(lastClaimed);
        uint8 prevMonth = dateTime.getMonth(lastClaimed);
        uint8 prevDay = dateTime.getDay(lastClaimed);

        if (
            refreshHours == 24 && !isSameDay(prevYear, prevMonth, prevDay, currentYear, currentMonth, currentDay)
                || block.timestamp - lastClaimed >= refreshHours * 1 hours
        ) {
            _incrementTaskPoints(user, task, cs.taskBasePoints[task]);
        }
    }

    function incrementNestPoints(address user, uint256 amount) external {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();

        require(
            msg.sender == cs.taskContractAddresses[CheckInStorage.Task.NEST],
            "Only Nest smart contract can call this function"
        );

        _incrementTaskPoints(user, CheckInStorage.Task.NEST, amount);
    }

    function _setTaskPoints(address user) internal {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        CheckInStorage.UserInfo storage userInfo = cs.users[user];

        // Code is not gas-optimized, but we'll delete this function later
        if (
            userInfo.flightPoints >= userInfo.taskPoints[CheckInStorage.Task.FLIGHT]
                || userInfo.faucetPoints >= userInfo.taskPoints[CheckInStorage.Task.FAUCET_ETH]
                || userInfo.rwaStakingPoints >= userInfo.taskPoints[CheckInStorage.Task.NEST]
                || userInfo.oracleGamePoints >= userInfo.taskPoints[CheckInStorage.Task.SUPRA]
        ) {
            userInfo.taskPoints[CheckInStorage.Task.FLIGHT] = userInfo.flightPoints;
            userInfo.taskPoints[CheckInStorage.Task.FAUCET_ETH] = userInfo.faucetPoints;
            userInfo.taskPoints[CheckInStorage.Task.NEST] = userInfo.rwaStakingPoints;
            userInfo.taskPoints[CheckInStorage.Task.SUPRA] = userInfo.oracleGamePoints;
            userInfo.lastClaimed[CheckInStorage.Task.FAUCET_ETH] = cs.faucetLastClaimed[user]["ETH"];
            userInfo.lastClaimed[CheckInStorage.Task.FAUCET_GOON] = cs.faucetLastClaimed[user]["P"];
            userInfo.lastClaimed[CheckInStorage.Task.FAUCET_USDC] = cs.faucetLastClaimed[user]["USDC"];
        }
    }

    function _incrementTaskPoints(address user, CheckInStorage.Task task, uint256 amount) internal {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();

        cs.users[user].taskPoints[task] += amount;
        cs.users[user].lastClaimed[task] = block.timestamp;

        emit TaskPointsUpdated(user, getTaskPoints(user));
    }

    function _adminSetUserPoints(address user, CheckInStorage.UserPoints calldata points) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        CheckInStorage.UserInfo storage userInfo = cs.users[user];
        userInfo.flightPoints = points.flightPoints;
        userInfo.faucetPoints = points.faucetPoints;
        userInfo.rwaStakingPoints = points.rwaStakingPoints;
        userInfo.oracleGamePoints = points.oracleGamePoints;

        _setTaskPoints(user);
    }

    function _adminSetUserTaskPoints(address user, uint256[] calldata taskPoints) public onlyRole(ADMIN_ROLE) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        for (uint256 i = 0; i < taskPoints.length; i++) {
            cs.users[user].taskPoints[CheckInStorage.Task(i)] = taskPoints[i];
        }
        _incrementTaskPoints(user, CheckInStorage.Task.FLIGHT, 0);
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
        uint256[] memory taskPoints = new uint256[](tasksLength);
        for (uint256 i = 0; i < tasksLength; i++) {
            taskPoints[i] = cs.users[user].taskPoints[CheckInStorage.Task(i)];
        }
        return taskPoints;
    }

    function getUsersTaskPoints(address[] memory _users) public view returns (uint256[][] memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;
        uint256[][] memory res = new uint256[][](_users.length);

        for (uint256 i = 0; i < _users.length; i++) {
            uint256[] memory taskPoints = new uint256[](tasksLength);
            for (uint256 j = 0; j < tasksLength; j++) {
                taskPoints[j] = cs.users[_users[i]].taskPoints[CheckInStorage.Task(j)];
            }
            res[i] = taskPoints;
        }
        return res;
    }

    function getTaskLastClaimed(address user) public view returns (uint256[] memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;
        uint256[] memory lastClaimed = new uint256[](tasksLength);
        for (uint256 i = 0; i < tasksLength; i++) {
            lastClaimed[i] = cs.users[user].taskPoints[CheckInStorage.Task(i)];
        }
        return lastClaimed;
    }

    function getUsersTaskLastClaimed(address[] memory _users) public view returns (uint256[][] memory) {
        CheckInStorage.Storage storage cs = CheckInStorage.getStorage();
        uint256 tasksLength = uint256(type(CheckInStorage.Task).max) + 1;
        uint256[][] memory res = new uint256[][](_users.length);

        for (uint256 i = 0; i < _users.length; i++) {
            uint256[] memory lastClaimed = new uint256[](tasksLength);
            for (uint256 j = 0; j < tasksLength; j++) {
                lastClaimed[j] = cs.users[_users[i]].lastClaimed[CheckInStorage.Task(j)];
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

        return CheckInStorage.UserData(
            userInfo.class,
            userInfo.streakCount,
            userInfo.reRolls,
            cs.weeklyCheckIns[user],
            getTaskPoints(user),
            getTaskLastClaimed(user)
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
