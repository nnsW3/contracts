// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./stRWA.sol";
import "./GOON.sol";
import "./NEST.sol";
import "./interfaces/IDateTime.sol";
import "./interfaces/ICheckin.sol";
import "./CheckInStorage.sol";

contract RWAStaking is UUPSUpgradeable, AccessControlUpgradeable {
    stRWA private _stRwaToken;
    GOON private _goonToken;
    NEST private _nestToken;
    IERC20 private _goonUsdToken;
    address private _admin;
    uint256 private _APR;
    uint256 private _lastRebaseTimestamp;

    mapping(address => uint256) public lastAccumulated;
    mapping(address => uint256) public unclaimedRewards;
    uint256 private constant SECONDS_PER_DAY = 86400;

    IDateTime private _dateTime;
    ICheckIn public checkIn;

    function initialize(
        address stRwaTokenAddress,
        address goonUsdTokenAddress,
        address goonToken,
        address nestToken,
        address dateTimeAddress,
        address checkInAddress
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();

        _stRwaToken = stRWA(stRwaTokenAddress);
        _goonToken = GOON(goonToken);
        _nestToken = NEST(nestToken);
        _goonUsdToken = IERC20(goonUsdTokenAddress);
        _dateTime = IDateTime(dateTimeAddress);
        checkIn = ICheckIn(checkInAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");

        require(_goonUsdToken.transferFrom(msg.sender, address(this), amount), "goonUSD transferFrom failed");

        _stRwaToken.mint(msg.sender, amount);

        accumulateRewards(msg.sender);

        checkIn.incrementTaskPoints(msg.sender, CheckInStorage.Task.NEST);
    }

    function unstake(uint256 amount) external {
        require(_stRwaToken.balanceOf(msg.sender) >= amount, "Insufficient stRWA balance");

        accumulateRewards(msg.sender);

        uint256 goonUsdAmount = _stRwaToken.balanceOf(msg.sender);
        _stRwaToken.burn(msg.sender, amount);

        require(_goonUsdToken.transfer(msg.sender, goonUsdAmount), "goonUSD transfer failed");
    }

    function claim() public {
        accumulateRewards(msg.sender);

        uint256 rewards = unclaimedRewards[msg.sender];

        if (rewards > 0) {
            uint256 goonRewards = (rewards * 2) / 1000;
            require(_goonToken.transfer(msg.sender, goonRewards), "$GOON transfer failed");

            uint256 nestRewards = rewards * 2;
            require(_nestToken.transfer(msg.sender, nestRewards), "$NEST transfer failed");

            uint256 miles = 1 + ((rewards * 2) / 100 - 1) / 1e18;
            checkIn.incrementNestPoints(msg.sender, miles);
        } else {
            rewards = 0;
        }

        unclaimedRewards[msg.sender] = 0;
    }

    function getUnclaimedRewards(address user) external view returns (uint256, uint256, uint256) {
        uint256 rewards = unclaimedRewards[user];
        uint256 goonRewards = (rewards * 2) / 1000;
        uint256 nestRewards = rewards * 2;
        uint256 miles = 1 + ((rewards * 2) / 100 - 1) / 1e18;

        return (goonRewards, nestRewards, miles);
    }

    function setAPR(uint256 APR) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _APR = APR;
    }

    function rebase() public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_dateTime.getHour(block.timestamp) == 0, "RWAStaking: rebase can only be called once per day");

        uint16 prevYear = _dateTime.getYear(_lastRebaseTimestamp);
        uint8 prevMonth = _dateTime.getMonth(_lastRebaseTimestamp);
        uint8 prevDay = _dateTime.getDay(_lastRebaseTimestamp);
        uint16 currentYear = _dateTime.getYear(block.timestamp);
        uint8 currentMonth = _dateTime.getMonth(block.timestamp);
        uint8 currentDay = _dateTime.getDay(block.timestamp);

        require(
            isNextDay(prevYear, prevMonth, prevDay, currentYear, currentMonth, currentDay),
            "RWAStaking: rebase already called today"
        );

        uint256 rewardMultiplierIncrement = _APR / 365;

        _stRwaToken.addRewardMultiplier(rewardMultiplierIncrement);

        _lastRebaseTimestamp = block.timestamp;
    }

    function getAccumulatedRewards(address user) internal view returns (uint256) {
        uint256 userStake = _stRwaToken.balanceOf(user);
        uint256 previousMidnight = block.timestamp - (block.timestamp % SECONDS_PER_DAY);
        uint256 lastMidnight = lastAccumulated[user] - (lastAccumulated[user] % SECONDS_PER_DAY);
        uint256 n = (previousMidnight - lastMidnight) / SECONDS_PER_DAY;

        uint256 rateTo18 = 36500e18 / (36500 + _APR);
        uint256 rewards = userStake * (1e18 - power(rateTo18, n)) / (1e18 - rateTo18);

        return rewards;
    }

    function accumulateRewards(address user) internal {
        uint256 rewards = getAccumulatedRewards(user);
        unclaimedRewards[user] += rewards;
        lastAccumulated[user] = block.timestamp;
    }

    function power(uint256 rateTo18, uint256 n) internal pure returns (uint256) {
        uint256 resTo18 = 1e18;
        for (uint256 i = 0; i < n; i++) {
            resTo18 = (resTo18 * rateTo18) / 1e18;
        }
        return resTo18;
    }

    function isNextDay(
        uint16 lastYear,
        uint8 lastMonth,
        uint8 lastDay,
        uint16 currentYear,
        uint8 currentMonth,
        uint8 currentDay
    ) internal view returns (bool) {
        uint256 lastDateTimestamp = _dateTime.toTimestamp(lastYear, lastMonth, lastDay);
        uint256 nextDayTimestamp = lastDateTimestamp + SECONDS_PER_DAY;

        uint16 nextDayYear = _dateTime.getYear(nextDayTimestamp);
        uint8 nextDayMonth = _dateTime.getMonth(nextDayTimestamp);
        uint8 nextDayDay = _dateTime.getDay(nextDayTimestamp);

        return (nextDayYear == currentYear) && (nextDayMonth == currentMonth) && (nextDayDay == currentDay);
    }
}
