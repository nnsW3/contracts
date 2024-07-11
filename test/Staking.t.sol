// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/NestStaking.sol";
import "../src/stRWA.sol";
import "../src/GOON.sol";
import "../src/goonUSD.sol";
import "../src/NEST.sol";
import "../src/DateTime.sol";
import "../src/CheckIn.sol";
import "../src/CheckInStorage.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract NestStakingTest is Test {
    NestStaking nestStaking;
    stRWA stRwaToken;
    GOON goonToken;
    goonUSD goonUsdToken;
    NEST nestToken;
    DateTime dateTime;
    CheckIn checkIn;
    address user = address(0x1234);
    address admin = address(0x1);

    function setUp() public {
        vm.startPrank(admin);
        address goonProxy = Upgrades.deployUUPSProxy("GOON.sol", abi.encodeCall(GOON.initialize, (admin)));
        goonToken = GOON(goonProxy);

        address goonUsdProxy = Upgrades.deployUUPSProxy("goonUSD.sol", abi.encodeCall(goonUSD.initialize, (admin)));
        goonUsdToken = goonUSD(goonUsdProxy);

        address nestProxy = Upgrades.deployUUPSProxy("NEST.sol", abi.encodeCall(NEST.initialize, (admin)));
        nestToken = NEST(nestProxy);
        address stRWAProxy =
            Upgrades.deployUUPSProxy("stRWA.sol", abi.encodeCall(stRWA.initialize, ("Stake RWA Token", "stRWA", admin)));
        stRwaToken = stRWA(stRWAProxy);

        dateTime = new DateTime();
        checkIn = new CheckIn();
        nestStaking = new NestStaking();

        checkIn.initialize(admin, address(dateTime), address(0));

        nestStaking.initialize(
            address(stRwaToken),
            address(goonToken),
            address(goonUsdToken),
            address(nestToken),
            address(dateTime),
            address(checkIn)
        );

        // Mint some tokens for the user
        //stRwaToken.grantRole(stRwaToken.DEFAULT_ADMIN_ROLE(), address(nestStaking));
        stRwaToken.grantRole(stRwaToken.MINTER_ROLE(), address(nestStaking));
        //goonToken.grantRole(goonToken.DEFAULT_ADMIN_ROLE(), address(nestStaking));
        //goonUsdToken.grantRole(goonUsdToken.DEFAULT_ADMIN_ROLE(), address(nestStaking));
        //nestToken.grantRole(nestToken.DEFAULT_ADMIN_ROLE(), address(nestStaking));
        stRwaToken.grantRole(stRwaToken.BURNER_ROLE(), address(nestStaking));
        checkIn._adminSetContract(CheckInStorage.Task.NEST, address(nestStaking));
        stRwaToken.setNestStaking(address(nestStaking));

        goonUsdToken.mint(user, 100000000 ether);
        goonToken.mint(address(nestStaking), 1000000000000 ether);
        goonUsdToken.mint(address(nestStaking), 100000000000 ether);
        nestToken.mint(address(nestStaking), 100000000000 ether);
        vm.stopPrank();

        vm.prank(user);
        goonUsdToken.approve(address(nestStaking), 100000000 ether);
    }

    function testStake() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        nestStaking.stake(stakeAmount);
        vm.stopPrank();

        assertEq(stRwaToken.balanceOf(user), stakeAmount);
        //assertEq(goonUsdToken.balanceOf(user), 900 ether);
    }

    function testUnstake() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        nestStaking.stake(stakeAmount);
        nestStaking.unstake(stakeAmount);
        vm.stopPrank();

        assertEq(stRwaToken.balanceOf(user), 0);
        //assertEq(goonUsdToken.balanceOf(user), 1000 ether);
    }

    function testRebase() public {
        vm.warp(dateTime.toTimestamp(2024, 5, 7, 10, 0, 0));
        uint256 stakeAmount = 1000 ether;

        vm.startPrank(user);
        nestStaking.stake(stakeAmount);
        vm.stopPrank();

        // Fast forward time to the next day
        vm.warp(dateTime.toTimestamp(2024, 5, 8, 0, 0, 1));

        vm.prank(admin);
        nestStaking.rebase();

        vm.warp(dateTime.toTimestamp(2024, 5, 8, 0, 0, 1));

        vm.expectRevert("NestStaking: rebase already called today");
        vm.prank(admin);
        nestStaking.rebase();

        uint256 unclaim = nestStaking.getAccumulatedRewards(user);
        console.logUint(unclaim);

        (uint256 goonRewards, uint256 nestRewards, uint256 miles) = nestStaking.getUnclaimedRewards(user);
        console.logUint(goonRewards);
        console.logUint(nestRewards);
        console.logUint(miles);

        vm.prank(user);
        nestStaking.claim();
        uint256 Base = 1e18;
        uint256 apr = 40;
        uint256 stRWAbalance = apr * 1e18 / (365 * 100);
        stRWAbalance = Base + stRWAbalance;
        stRWAbalance = 100 * stRWAbalance;

        uint256 expectedRewards = ((stakeAmount) + (stakeAmount * 40 / (365 * 100)));
    }

    function testRebaseStake() public {
        vm.warp(dateTime.toTimestamp(2024, 5, 7, 10, 0, 0));
        uint256 stakeAmount = 1000 ether;

        vm.startPrank(user);
        nestStaking.stake(stakeAmount);
        vm.stopPrank();

        // Fast forward time to the next day
        vm.warp(dateTime.toTimestamp(2024, 5, 8, 0, 0, 1));

        vm.prank(admin);
        nestStaking.rebase();

        (uint256 goonRewards, uint256 nestRewards, uint256 miles) = nestStaking.getUnclaimedRewards(user);
        console.logUint(goonRewards);
        console.logUint(nestRewards);
        console.logUint(miles);

        vm.warp(dateTime.toTimestamp(2024, 5, 8, 11, 0, 1));

        vm.startPrank(user);
        nestStaking.stake(stakeAmount);
        vm.stopPrank();


        vm.warp(dateTime.toTimestamp(2024, 5, 9, 0, 0, 1));

        vm.prank(admin);
        nestStaking.rebase();

        ( goonRewards,  nestRewards,  miles) = nestStaking.getUnclaimedRewards(user);
        console.logUint(goonRewards);
        console.logUint(nestRewards);
        console.logUint(miles);

        vm.prank(user);
        nestStaking.claim();

        //assertEq(stRwaToken.rewardMultiplier(), expectedRewards);
    }

    function testRebaseUnstake() public {
        vm.warp(dateTime.toTimestamp(2024, 5, 7, 10, 0, 0));
        uint256 stakeAmount = 1000 ether;

        vm.startPrank(user);
        nestStaking.stake(stakeAmount);
        vm.stopPrank();

        // Fast forward time to the next day
        vm.warp(dateTime.toTimestamp(2024, 5, 8, 0, 0, 1));
        vm.prank(admin);
        nestStaking.rebase();

        //vm.warp(dateTime.toTimestamp(2024, 5, 9, 0, 0, 1));
        vm.prank(user);
        nestStaking.unstake(stakeAmount);

        vm.prank(user);
        nestStaking.claim();
        //assertEq(stRwaToken.rewardMultiplier(), expectedRewards);
    }
}
