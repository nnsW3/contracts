// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/RWAFactory.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../src/Checkin.sol";
import "../src/DateTime.sol";
import "../src/CheckInStorage.sol";

contract RWAFactoryTest is Test {
    RWAFactory public rwaFactory;
    address public admin;
    address public user;

    DateTime dateTime;
    CheckIn checkIn;

    function setUp() public {
        dateTime = new DateTime();
        checkIn = new CheckIn();
        vm.startPrank(address(this));

        checkIn.initialize(address(this), address(dateTime), address(0));

        user = address(1);

        rwaFactory = new RWAFactory();
        rwaFactory.initialize(address(checkIn));

        checkIn._adminSetContract(CheckInStorage.Task.RWA_LAUNCHER, address(rwaFactory));

        rwaFactory.grantRole(rwaFactory.ADMIN_ROLE(), admin);
        vm.stopPrank();
    }

    function testCreateToken() public {
        vm.startPrank(user);
        rwaFactory.createToken("Token1", "TKN1", "A unique token", 0, "ipfs://image1");
        vm.stopPrank();

        (, uint256 count) = rwaFactory.getRWACategory(0);
        assertEq(count, 1);
    }

    // Should fail because the token cannot be initialized twice
    function testFailMintingTwice() public {
        vm.startPrank(user);
        address token = rwaFactory.createToken("Token1", "TKN1", "A unique token", 0, "ipfs://image1");
        vm.stopPrank();

        RWA newToken = RWA(token);
        newToken.initialize("Token1", "TKN1", "A unique token", "Hel", "ipfs://image1", user);
    }
}
