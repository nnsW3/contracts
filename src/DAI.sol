// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";

contract DAI is ERC20 {
    constructor(uint256 _initialSupply) ERC20("Dai Stablecoin", "DAI") {
      _mint(msg.sender, _initialSupply);
    }
}