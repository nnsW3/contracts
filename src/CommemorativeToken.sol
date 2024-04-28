// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin-contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin-contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract CommemorativeToken is ERC721URIStorage {
    uint256 private _nextTokenId;

    constructor() ERC721("Plume x Bitget NFT", "NFT") {}

    function mint() public returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, "https://assets.plumenetwork.xyz/metadata/plume-bitget-nft.json");
        return tokenId;
    }
}
