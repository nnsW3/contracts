// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract RolexYachtMaster40 is Ownable, ERC721 {
    error NFTAlreadyMinted();
    bool private _minted;

    constructor() ERC721("Rolex Yacht-Master 40", "") {}

    function mint(address owner) public onlyOwner returns (uint256) {
        if (_minted) {
            revert NFTAlreadyMinted();
        }
        _safeMint(owner, 0);
        _minted = true;
        return 0;
    }
}
