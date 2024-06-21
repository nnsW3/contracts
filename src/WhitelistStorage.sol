// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library WhitelistStorage {
    bytes32 public constant WHITELIST_ADMIN_ROLE = keccak256("WHITELIST_ADMIN_ROLE");

    struct Storage {
        mapping(address => bool) whitelist;
        mapping(uint256 => uint256) claimedBitMap;
    }

    function getStorage() internal pure returns (Storage storage ws) {
        bytes32 position = keccak256("whitelist.storage");
        assembly {
            ws.slot := position
        }
    }
}
