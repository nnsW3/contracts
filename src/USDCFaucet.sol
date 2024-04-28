// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
}

contract USDCFaucet {
    uint256 public tokenAmount = 100000 * 10 ** 6;
    IERC20 public tokenInstance;
    event TokensWithdrawn(address indexed recipient, uint256 amount);

    constructor(address _tokenInstance) {
        tokenInstance = IERC20(_tokenInstance);
    }

    function requestTokens() public {
        tokenInstance.transfer(msg.sender, tokenAmount);
        emit TokensWithdrawn(msg.sender, tokenAmount);
    }
}
