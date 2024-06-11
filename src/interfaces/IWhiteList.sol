// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IWhitelist {
    // Whitelist
    function addAddressToWhitelist(address addressToAdd) external;
    function removeAddressFromWhitelist(address addressToRemove) external;
    function addToWhitelist(address[] calldata addresses) external;
    function removeFromWhitelist(address[] calldata addresses) external;

    // Claim
    function isClaimed(uint256 index) external view returns (bool);
    function claim(uint256 index, address account) external;

    // Check if an address is whitelisted
    function isWhitelisted(address account) external view returns (bool);
}
