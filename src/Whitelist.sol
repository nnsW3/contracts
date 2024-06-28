// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./WhitelistStorage.sol";
import "./interfaces/IWhitelist.sol";

error AlreadyClaimed();
error InvalidWhitelist();

contract Whitelist is Initializable, AccessControlUpgradeable, UUPSUpgradeable, IWhitelist {
    using WhitelistStorage for WhitelistStorage.Storage;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function initialize(address admin) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(WhitelistStorage.WHITELIST_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // Single address
    function addAddressToWhitelist(address addressToAdd)
        external
        override
        onlyRole(WhitelistStorage.WHITELIST_ADMIN_ROLE)
    {
        WhitelistStorage.Storage storage ws = WhitelistStorage.getStorage();
        ws.whitelist[addressToAdd] = true;
    }

    function removeAddressFromWhitelist(address addressToRemove)
        external
        override
        onlyRole(WhitelistStorage.WHITELIST_ADMIN_ROLE)
    {
        WhitelistStorage.Storage storage ws = WhitelistStorage.getStorage();
        delete ws.whitelist[addressToRemove];
    }

    // Batch address
    function addToWhitelist(address[] calldata addresses)
        external
        override
        onlyRole(WhitelistStorage.WHITELIST_ADMIN_ROLE)
    {
        WhitelistStorage.Storage storage ws = WhitelistStorage.getStorage();
        for (uint256 i = 0; i < addresses.length; i++) {
            ws.whitelist[addresses[i]] = true;
        }
    }

    function removeFromWhitelist(address[] calldata addresses)
        external
        override
        onlyRole(WhitelistStorage.WHITELIST_ADMIN_ROLE)
    {
        WhitelistStorage.Storage storage ws = WhitelistStorage.getStorage();
        for (uint256 i = 0; i < addresses.length; i++) {
            delete ws.whitelist[addresses[i]];
        }
    }

    // Claim
    function isClaimed(uint256 index) public view override returns (bool) {
        WhitelistStorage.Storage storage ws = WhitelistStorage.getStorage();
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = ws.claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function claim(uint256 index, address account) external override {
        if (isClaimed(index) && index != 0) revert AlreadyClaimed();
        if (!isWhitelisted(account)) revert InvalidWhitelist();
        _setClaimed(index);
    }

    // Whitelist checking
    function isWhitelisted(address account) public view override returns (bool) {
        WhitelistStorage.Storage storage ws = WhitelistStorage.getStorage();
        return ws.whitelist[account];
    }

    // Private helper to mark an index as claimed
    function _setClaimed(uint256 index) private {
        WhitelistStorage.Storage storage ws = WhitelistStorage.getStorage();
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        ws.claimedBitMap[claimedWordIndex] |= (1 << claimedBitIndex);
    }

    // View functions for storage variables
    function getWhitelistStatus(address account) public view returns (bool) {
        WhitelistStorage.Storage storage ws = WhitelistStorage.getStorage();
        return ws.whitelist[account];
    }

    function getClaimedBitMap(uint256 index) public view returns (uint256) {
        WhitelistStorage.Storage storage ws = WhitelistStorage.getStorage();
        return ws.claimedBitMap[index];
    }

    function getClaimedStatus(uint256 index) public view returns (bool) {
        return isClaimed(index);
    }
}
