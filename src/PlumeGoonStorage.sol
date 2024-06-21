// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

library PlumeGoonStorage {
    struct Storage {
        address admin;
        mapping(string => uint256) tokenURIs; // to ensure token uri is unique i.e same nft cannot be claimed by another user
        mapping(address => bool) hasMinted;
    }

    function getStorage() internal pure returns (Storage storage ps) {
        bytes32 position = keccak256("plumegoon.storage");
        assembly {
            ps.slot := position
        }
    }
}
