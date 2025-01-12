// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "../CheckInStorage.sol";

interface ICheckIn {
    function getReRolls(address user) external view returns (uint256);
    function incrementPoints(address user, uint8 tier) external;
    function incrementFaucetPoints(address user, string memory token) external;
    function incrementTaskPoints(address user, CheckInStorage.Task task) external;
    function incrementNestPoints(address user, uint256 amount) external;
    function decrementReRolls(address user) external;
}
