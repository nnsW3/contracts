// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ECDSA} from "@openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";

interface ICheckIn {
    function faucetCheckIn(address user, string calldata token) external;
}

contract Faucet {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    address public constant ETH_ADDRESS = address(1);

    uint256 public etherAmount = 0.001 ether;
    uint256 public tokenAmount = 1000;

    address public admin;
    ICheckIn public checkIn;
    mapping(string => address) public tokens;
    mapping(bytes32 => bool) public usedNonces;

    event TokenSent(address indexed recipient, uint256 amount, string tokenName);
    event Withdrawn(address indexed recipient, uint256 amount, string tokenName);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event CheckInContractChanged(address indexed oldCheckInContract, address indexed newCheckInContract);

    constructor(address _admin, address checkInContract, string[] memory tokenNames, address[] memory tokenAddresses) {
        require(_admin != address(0), "Admin address must not be empty");
        require(checkInContract != address(0), "CheckIn contract address must not be empty");
        require(tokenNames.length > 0, "Token names must not be empty");
        require(tokenNames.length == tokenAddresses.length, "Length of token names and addresses must be equal");

        admin = _admin;
        checkIn = ICheckIn(checkInContract);

        bytes32 ethHash = keccak256(abi.encodePacked("ETH"));

        for (uint256 i = 0; i < tokenNames.length; i++) {
            if (keccak256(bytes(tokenNames[i])) == ethHash) {
                tokens[tokenNames[i]] = ETH_ADDRESS;
            } else {
                tokens[tokenNames[i]] = tokenAddresses[i];
            }
        }
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");

        _;
    }

    modifier onlySignedByAdmin(string calldata token, bytes32 salt, bytes calldata signature) {
        bytes32 message = keccak256(abi.encodePacked(msg.sender, token, salt));

        require(!usedNonces[message], "Signature is already used");

        require(message.toEthSignedMessageHash().recover(signature) == admin, "Invalid admin signature");

        usedNonces[message] = true;

        _;
    }

    function getToken(string calldata token, bytes32 salt, bytes calldata signature)
        external
        onlySignedByAdmin(token, salt, signature)
    {
        address tokenAddress = tokens[token];

        require(tokenAddress != address(0), "Invalid token");

        if (tokenAddress == ETH_ADDRESS) {
            require(address(this).balance >= etherAmount, "Insufficient balance");

            (bool success,) = msg.sender.call{value: etherAmount, gas: 2300}("");

            require(success, "Failed to send Ether");
        } else {
            IERC20Metadata tokenContract = IERC20Metadata(tokens[token]);
            uint8 decimals = tokenContract.decimals();
            tokenContract.transfer(msg.sender, tokenAmount * (10 ** decimals));
        }

        emit TokenSent(msg.sender, tokenAmount, token);

        checkIn.faucetCheckIn(msg.sender, token);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "New admin address must not be empty");

        emit AdminChanged(admin, newAdmin);

        admin = newAdmin;
    }

    function setCheckInContract(address newCheckInContract) external onlyAdmin {
        require(newCheckInContract != address(0), "New checkIn contract address must not be empty");

        emit CheckInContractChanged(address(checkIn), newCheckInContract);

        checkIn = ICheckIn(newCheckInContract);
    }

    function setEtherAmount(uint256 amount) external onlyAdmin {
        etherAmount = amount;
    }

    function setTokenAmount(uint256 amount) external onlyAdmin {
        tokenAmount = amount;
    }

    function withdrawToken(string calldata token, uint256 amount, address payable recipient) external onlyAdmin {
        address tokenAddress = tokens[token];

        require(tokenAddress != address(0), "Invalid token");

        if (tokenAddress == ETH_ADDRESS) {
            require(address(this).balance >= amount, "Insufficient balance");

            (bool success,) = recipient.call{value: amount, gas: 2300}("");

            require(success, "Failed to send Ether");
        } else {
            IERC20Metadata tokenContract = IERC20Metadata(tokens[token]);
            tokenContract.transfer(recipient, amount);
        }

        emit Withdrawn(recipient, amount, token);
    }

    receive() external payable {}
}
