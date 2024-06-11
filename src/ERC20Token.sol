// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    ERC20PermitUpgradeable,
    NoncesUpgradeable
} from "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20PausableUpgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20VotesUpgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {ERC20FlashMintUpgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20FlashMintUpgradeable.sol";

contract ERC20Token is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    ERC20FlashMintUpgradeable,
    UUPSUpgradeable
{
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint8 private _decimals;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        uint8 customDecimals,
        address defaultAdmin,
        address minter,
        address upgrader,
        address pauser
    ) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Burnable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _decimals = customDecimals;

        require(pauser != address(0), "Provide address for Pauser");
        __ERC20Pausable_init();
        _grantRole(PAUSER_ROLE, pauser);

        __ERC20Permit_init(name);
        __ERC20FlashMint_init();
        __ERC20Votes_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, upgrader);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20VotesUpgradeable)
    {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(owner);
    }

    function getVersion() public pure virtual returns (string memory) {
        return "v1";
    }
}

contract ERC20TokenV2 is ERC20Token {
    function getVersion() public pure override returns (string memory) {
        return "v2";
    }
}
