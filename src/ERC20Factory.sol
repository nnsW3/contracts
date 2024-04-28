// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20Token} from "./ERC20Token.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ERC20Factory is Ownable {
    address public implementationAddress;

    event TokenCreated(address indexed tokenAddress);

    address[] public allTokens;

    constructor(address _initialImplementation) Ownable(msg.sender) {
        implementationAddress = _initialImplementation;
    }

    function createToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        address defaultAdmin,
        address minter,
        address upgrader,
        address pauser
    ) external onlyOwner returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            ERC20Token.initialize.selector, name, symbol, decimals, defaultAdmin, minter, upgrader, pauser
        );
        ERC1967Proxy proxy = new ERC1967Proxy(implementationAddress, initData);

        address newTokenAddress = address(proxy);

        allTokens.push(newTokenAddress);
        emit TokenCreated(newTokenAddress);

        return newTokenAddress;
    }

    function getAllTokens() external view returns (address[] memory) {
        return allTokens;
    }
}
