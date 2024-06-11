// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface ICheckIn {
    function getReRolls(address user) external view returns (uint256);
    function incrementPoints(string memory _tokenUri, address user, bytes memory signature, uint8 tier) external;
    function incrementFaucetPoints(address user, string memory token) external;
}
