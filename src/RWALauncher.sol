// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract RWA is Initializable, ERC721Upgradeable {
    string public description;
    string public rwaType;
    string public image;
    address public creator;

    function initialize(
        string memory name,
        string memory symbol,
        string memory _description,
        string memory _rwaType,
        string memory _image,
        address _creator
    ) public initializer {
        __ERC721_init(name, symbol);

        description = _description;
        rwaType = _rwaType;
        image = _image;
        creator = _creator;
        _mint(_creator, 1);
    }

    function getName() public view returns (string memory) {
        return name();
    }

    function getSymbol() public view returns (string memory) {
        return symbol();
    }

    function getRWAType() public view returns (string memory) {
        return rwaType;
    }

    function getCreator() public view returns (address) {
        return creator;
    }
}
