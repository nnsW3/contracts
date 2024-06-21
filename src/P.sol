// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";

contract P is ERC20 {
    constructor(uint256 _initialSupply) ERC20("Plume", "P") {
        _mint(msg.sender, _initialSupply);
    }
}
