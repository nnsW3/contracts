// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin-contracts/access/AccessControl.sol";
import "./interfaces/IWhitelist.sol";

error AlreadyClaimed();
error InvalidWhitelist();

contract Whitelist is IWhitelist, AccessControl {
    bytes32 public constant WHITELIST_ADMIN_ROLE = keccak256("WHITELIST_ADMIN_ROLE");
    mapping(address => bool) public whitelist;
    mapping(uint256 => uint256) private claimedBitMap;

    constructor() {
        _grantRole(WHITELIST_ADMIN_ROLE, msg.sender);
    }

    // Single address
    function addAddressToWhitelist(address addressToAdd) external override onlyRole(WHITELIST_ADMIN_ROLE) {
        whitelist[addressToAdd] = true;
    }

    function removeAddressFromWhitelist(address addressToRemove) external override onlyRole(WHITELIST_ADMIN_ROLE) {
        delete whitelist[addressToRemove];
    }

    // Batch address
    function addToWhitelist(address[] calldata addresses) external override onlyRole(WHITELIST_ADMIN_ROLE) {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = true;
        }
    }

    function removeFromWhitelist(address[] calldata addresses) external override onlyRole(WHITELIST_ADMIN_ROLE) {
        for (uint256 i = 0; i < addresses.length; i++) {
            delete whitelist[addresses[i]];
        }
    }

    // Claim
    function isClaimed(uint256 index) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function claim(uint256 index, address account) external override {
        if (isClaimed(index) && index != 0) revert AlreadyClaimed();
        if (!isWhitelisted(account)) revert InvalidWhitelist();
        _setClaimed(index);
    }

    // Whitelist checking
    function isWhitelisted(address account) public view override returns (bool) {
        return whitelist[account];
    }

    // Private helper to mark an index as claimed
    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] |= (1 << claimedBitIndex);
    }
}
