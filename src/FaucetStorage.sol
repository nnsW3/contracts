// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ICheckIn} from "./interfaces/ICheckIn.sol";

library FaucetStorage {
    struct Storage {
        address admin;
        uint256 etherAmount;
        uint256 tokenAmount;
        ICheckIn checkIn;
        mapping(string => address) tokens;
        mapping(bytes32 => bool) usedNonces;
    }

    function getStorage() internal pure returns (Storage storage fs) {
        bytes32 position = keccak256("faucet.storage");
        assembly {
            fs.slot := position
        }
    }
}
