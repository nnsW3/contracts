// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC721} from "@openzeppelin-contracts/token/ERC721/ERC721.sol";

contract CommemorativeToken is ERC721 {
    uint256 private _nextTokenId;

    constructor() ERC721("Commemorative Token", "CNFT") {}

    function mint() public returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        return tokenId;
    }
}
