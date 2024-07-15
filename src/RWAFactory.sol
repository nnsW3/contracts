// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./RWALauncher.sol";
import "./interfaces/ICheckin.sol";
import "./CheckInStorage.sol";

/// @custom:oz-upgrades-from RWAFactory
contract RWAFactory is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    ICheckIn public checkIn;

    struct RWACategory {
        string name;
        uint256 count;
    }

    mapping(uint256 => RWACategory) public rwaCategories;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event TokenCreated(
        address indexed tokenAddress, string name, string symbol, string description, string rwaType, string image
    );

    function initialize(address checkInAddress) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        checkIn = ICheckIn(checkInAddress);

        // Initialize categories
        _addRWACategory(0, "Art");
        _addRWACategory(1, "Collectible Cards");
        _addRWACategory(2, "Farming");
        _addRWACategory(3, "Investment Alcohol");
        _addRWACategory(4, "Investment Cigars");
        _addRWACategory(5, "Investment Watch");
        _addRWACategory(6, "Rare Sneakers");
        _addRWACategory(7, "Real Estate");
        _addRWACategory(8, "Solar Energy");
        _addRWACategory(9, "Tokenized GPUs");
    }

    function createToken(
        string memory name,
        string memory symbol,
        string memory description,
        uint256 rwaType,
        string memory image
    ) external returns (address) {
        require(bytes(rwaCategories[rwaType].name).length > 0, "Invalid RWA type");

        rwaCategories[rwaType].count += 1;

        RWA newToken = new RWA();
        newToken.initialize(name, symbol, description, rwaCategories[rwaType].name, image, msg.sender);
        emit TokenCreated(address(newToken), name, symbol, description, rwaCategories[rwaType].name, image);

        checkIn.incrementTaskPoints(msg.sender, CheckInStorage.Task.RWA_LAUNCHER);

        return address(newToken);
    }

    function _addRWACategory(uint256 id, string memory name) internal {
        rwaCategories[id] = RWACategory(name, 0);
    }

    function addRWACategory(uint256 id, string memory name) external onlyRole(ADMIN_ROLE) {
        _addRWACategory(id, name);
    }

    function getRWACategory(uint256 id) external view returns (string memory name, uint256 count) {
        RWACategory storage category = rwaCategories[id];
        return (category.name, category.count);
    }

    function updateCheckInContract(address newCheckIn) external onlyRole(ADMIN_ROLE) {
        checkIn = ICheckIn(newCheckIn);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
