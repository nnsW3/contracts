// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ETHFaucet is Ownable {
    uint256 public constant tokenAmount = 0.01 ether;

    event ETHWithdrawn(address indexed recipient, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function sendETH(address payable _recipient) external onlyOwner {
        require(address(this).balance >= tokenAmount, "Not enough tokens in faucet");
        _recipient.transfer(tokenAmount);
        emit ETHWithdrawn(_recipient, tokenAmount);
    }

    receive() external payable {}
}
