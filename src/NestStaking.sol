// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./NestStakingStorage.sol";
import "./CheckInStorage.sol";

contract NestStaking is UUPSUpgradeable, AccessControlUpgradeable {
    using NestStakingStorage for NestStakingStorage.Storage;

    uint256 private constant SECONDS_PER_DAY = 86400;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 goonRewards, uint256 nestRewards, uint256 miles);

    function initialize(
        address stRwaTokenAddress,
        address goonTokenAddress,
        address goonUsdTokenAddress,
        address nestTokenAddress,
        address dateTimeAddress,
        address checkInAddress
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();

        NestStakingStorage.Storage storage rs = NestStakingStorage.getStorage();
        rs.stRwaToken = stRWA(stRwaTokenAddress);
        rs.goonToken = GOON(goonTokenAddress);
        rs.goonUsdToken = goonUSD(goonUsdTokenAddress);
        rs.nestToken = NEST(nestTokenAddress);
        rs.dateTime = IDateTime(dateTimeAddress);
        rs.checkIn = ICheckIn(checkInAddress);
        rs.APR = 40e18;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");

        NestStakingStorage.Storage storage rs = NestStakingStorage.getStorage();
        require(rs.goonUsdToken.transferFrom(msg.sender, address(this), amount), "goonUSD transferFrom failed");

        accumulateRewards(msg.sender);
        rs.stRwaToken.mint(msg.sender, amount);
        rs.checkIn.incrementTaskPoints(msg.sender, CheckInStorage.Task.NEST);

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        NestStakingStorage.Storage storage rs = NestStakingStorage.getStorage();
        require(rs.stRwaToken.balanceOf(msg.sender) >= amount, "Insufficient stRWA balance");

        accumulateRewards(msg.sender);
        rs.stRwaToken.burn(msg.sender, amount);
        require(rs.goonUsdToken.transfer(msg.sender, amount), "goonUSD transfer failed");

        emit Unstaked(msg.sender, amount);
    }

    function claim() public {
        NestStakingStorage.Storage storage rs = NestStakingStorage.getStorage();
        accumulateRewards(msg.sender);

        (uint256 goonRewards, uint256 nestRewards, uint256 miles) = getUnclaimedRewards(msg.sender);

        if (goonRewards > 0) {
            require(rs.goonToken.transfer(msg.sender, goonRewards), "$GOON transfer failed");
            require(rs.nestToken.transfer(msg.sender, nestRewards), "$NEST transfer failed");
            rs.checkIn.incrementNestPoints(msg.sender, miles);
            rs.unclaimedRewards[msg.sender] = 0;

            emit Claimed(msg.sender, goonRewards, nestRewards, miles);
        }
    }

    function getUnclaimedRewards(address user) public view returns (uint256, uint256, uint256) {
        NestStakingStorage.Storage storage rs = NestStakingStorage.getStorage();
        uint256 rewards = rs.unclaimedRewards[user] + getAccumulatedRewards(user);
        if (rewards == 0) {
            return (0, 0, 0);
        }
        uint256 goonRewards = (rewards * 2) / 1000;
        uint256 nestRewards = (rewards * 2);
        uint256 miles = 1 + ((rewards * 2) / 100 - 1) / 1e18;

        return (goonRewards, nestRewards, miles);
    }

    function setAPR(uint256 APR) external onlyRole(DEFAULT_ADMIN_ROLE) {
        NestStakingStorage.Storage storage rs = NestStakingStorage.getStorage();
        rs.APR = APR;
    }

    function rebase() public onlyRole(DEFAULT_ADMIN_ROLE) {
        NestStakingStorage.Storage storage rs = NestStakingStorage.getStorage();

        uint16 prevYear = rs.dateTime.getYear(rs.lastRebaseTimestamp);
        uint8 prevMonth = rs.dateTime.getMonth(rs.lastRebaseTimestamp);
        uint8 prevDay = rs.dateTime.getDay(rs.lastRebaseTimestamp);
        uint16 currentYear = rs.dateTime.getYear(block.timestamp);
        uint8 currentMonth = rs.dateTime.getMonth(block.timestamp);
        uint8 currentDay = rs.dateTime.getDay(block.timestamp);

        if (rs.lastRebaseTimestamp != 0) {
            require(
                isNextDay(prevYear, prevMonth, prevDay, currentYear, currentMonth, currentDay),
                "NestStaking: rebase already called today"
            );
        }

        uint256 rewardMultiplierIncrement = rs.APR / (100 * 365);
        rs.stRwaToken.addRewardMultiplier(rewardMultiplierIncrement);
        rs.lastRebaseTimestamp = block.timestamp;
    }

    function getAccumulatedRewards(address user) public view returns (uint256) {
        NestStakingStorage.Storage storage rs = NestStakingStorage.getStorage();
        uint256 userStake = rs.stRwaToken.balanceOf(user);
        if (userStake != 0 && rs.lastAccumulated[user] != 0) {
            uint256 previousMidnight = block.timestamp - (block.timestamp % SECONDS_PER_DAY);
            uint256 lastMidnight = rs.lastAccumulated[user] - (rs.lastAccumulated[user] % SECONDS_PER_DAY);
            uint256 n = (previousMidnight - lastMidnight) / SECONDS_PER_DAY;

            uint256 rateTo18 = 36500e36 / (36500e18 + rs.APR);
            uint256 rewards = userStake * (1e18 - power(rateTo18, n)) / (1e18 - rateTo18);

            return rewards;
        } else {
            return 0;
        }
    }

    function accumulateRewards(address user) internal {
        NestStakingStorage.Storage storage rs = NestStakingStorage.getStorage();
        uint256 rewards = getAccumulatedRewards(user);
        if (rewards != 0) {
            rs.unclaimedRewards[user] += rewards;
        }
        rs.lastAccumulated[user] = block.timestamp;
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
        NestStakingStorage.Storage storage rs = NestStakingStorage.getStorage();
        uint256 lastDateTimestamp = rs.dateTime.toTimestamp(lastYear, lastMonth, lastDay);
        uint256 nextDayTimestamp = lastDateTimestamp + SECONDS_PER_DAY;

        uint16 nextDayYear = rs.dateTime.getYear(nextDayTimestamp);
        uint8 nextDayMonth = rs.dateTime.getMonth(nextDayTimestamp);
        uint8 nextDayDay = rs.dateTime.getDay(nextDayTimestamp);

        return (nextDayYear == currentYear) && (nextDayMonth == currentMonth) && (nextDayDay == currentDay);
    }
}
