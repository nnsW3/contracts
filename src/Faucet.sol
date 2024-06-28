// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ICheckIn} from "./interfaces/ICheckIn.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./FaucetStorage.sol";

contract Faucet is Initializable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using FaucetStorage for FaucetStorage.Storage;

    address public constant ETH_ADDRESS = address(1);

    event TokenSent(address indexed recipient, uint256 amount, string tokenName);
    event Withdrawn(address indexed recipient, uint256 amount, string tokenName);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event CheckInContractChanged(address indexed oldCheckInContract, address indexed newCheckInContract);

    function initialize(
        address _admin,
        address checkInContract,
        string[] memory tokenNames,
        address[] memory tokenAddresses
    ) public initializer {
        require(_admin != address(0), "Admin address must not be empty");
        require(checkInContract != address(0), "CheckIn contract address must not be empty");
        require(tokenNames.length > 0, "Token names must not be empty");
        require(tokenNames.length == tokenAddresses.length, "Length of token names and addresses must be equal");

        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        fs.admin = _admin;
        fs.etherAmount = 0.001 ether;
        fs.tokenAmount = 1;
        fs.checkIn = ICheckIn(checkInContract);

        bytes32 ethHash = keccak256(abi.encodePacked("ETH"));

        for (uint256 i = 0; i < tokenNames.length; i++) {
            if (keccak256(bytes(tokenNames[i])) == ethHash) {
                fs.tokens[tokenNames[i]] = ETH_ADDRESS;
            } else {
                fs.tokens[tokenNames[i]] = tokenAddresses[i];
            }
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}

    modifier onlyAdmin() {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        require(msg.sender == fs.admin, "Only admin can call this function");
        _;
    }

    modifier onlySignedByAdmin(string calldata token, bytes32 salt, bytes calldata signature) {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        bytes32 message = keccak256(abi.encodePacked(msg.sender, token, salt));

        require(!fs.usedNonces[message], "Signature is already used");
        require(message.toEthSignedMessageHash().recover(signature) == fs.admin, "Invalid admin signature");

        fs.usedNonces[message] = true;
        _;
    }

    function getToken(string calldata token, bytes32 salt, bytes calldata signature)
        external
        onlySignedByAdmin(token, salt, signature)
    {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        address tokenAddress = fs.tokens[token];

        require(tokenAddress != address(0), "Invalid token");

        uint256 amount;
        if (tokenAddress == ETH_ADDRESS) {
            amount = fs.etherAmount;
            require(address(this).balance >= amount, "Insufficient balance");
            (bool success,) = msg.sender.call{value: amount, gas: 2300}("");
            require(success, "Failed to send Ether");
        } else {
            amount = fs.tokenAmount;
            IERC20Metadata tokenContract = IERC20Metadata(tokenAddress);
            uint8 decimals = tokenContract.decimals();
            tokenContract.transfer(msg.sender, amount * (10 ** decimals));
        }

        emit TokenSent(msg.sender, amount, token);

        fs.checkIn.incrementFaucetPoints(msg.sender, token);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        require(newAdmin != address(0), "New admin address must not be empty");

        emit AdminChanged(fs.admin, newAdmin);
        fs.admin = newAdmin;
    }

    function setCheckInContract(address newCheckInContract) external onlyAdmin {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        require(newCheckInContract != address(0), "New checkIn contract address must not be empty");

        emit CheckInContractChanged(address(fs.checkIn), newCheckInContract);
        fs.checkIn = ICheckIn(newCheckInContract);
    }

    function setEtherAmount(uint256 amount) external onlyAdmin {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        fs.etherAmount = amount;
    }

    function setTokenAmount(uint256 amount) external onlyAdmin {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        fs.tokenAmount = amount;
    }

    function withdrawToken(string calldata token, uint256 amount, address payable recipient) external onlyAdmin {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        address tokenAddress = fs.tokens[token];

        require(tokenAddress != address(0), "Invalid token");

        if (tokenAddress == ETH_ADDRESS) {
            require(address(this).balance >= amount, "Insufficient balance");
            (bool success,) = recipient.call{value: amount, gas: 2300}("");
            require(success, "Failed to send Ether");
        } else {
            IERC20Metadata tokenContract = IERC20Metadata(tokenAddress);
            tokenContract.transfer(recipient, amount);
        }

        emit Withdrawn(recipient, amount, token);
    }

    // View functions for storage variables

    function getAdmin() public view returns (address) {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        return fs.admin;
    }

    function getEtherAmount() public view returns (uint256) {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        return fs.etherAmount;
    }

    function getTokenAmount() public view returns (uint256) {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        return fs.tokenAmount;
    }

    function getCheckInContract() public view returns (address) {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        return address(fs.checkIn);
    }

    function getTokenAddress(string calldata token) public view returns (address) {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        return fs.tokens[token];
    }

    function isNonceUsed(bytes32 nonce) public view returns (bool) {
        FaucetStorage.Storage storage fs = FaucetStorage.getStorage();
        return fs.usedNonces[nonce];
    }

    receive() external payable {}
}
