// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./PlumeGoonStorage.sol";
import "./interfaces/IWhitelist.sol";
import "./interfaces/ICheckIn.sol";

contract PlumeGoon is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    ERC721PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using PlumeGoonStorage for PlumeGoonStorage.Storage;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    IWhitelist public whitelistContract;
    ICheckIn public checkInContract;

    event Minted(address indexed user, uint256 tokenId);
    event Rerolled(address indexed user, uint256 newtokenId, uint256 burnTokenId);

    function initialize(
        address _admin,
        string memory name,
        string memory symbol,
        address whitelistAddress,
        address checkInAddress,
        address pauser,
        address minter
    ) public initializer {
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        ps.admin = _admin;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, _admin);

        whitelistContract = IWhitelist(whitelistAddress);
        checkInContract = ICheckIn(checkInAddress);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    modifier _onlyWithAdminSignature(string memory _tokenUri, address user, bytes memory signature) {
        require(onlyWithAdminSignature(_tokenUri, user, signature), "Invalid signature");
        _;
    }

    function recoverSignerFromSignature(bytes32 message, bytes memory sig) internal pure returns (address) {
        require(sig.length == 65);

        uint8 v;
        bytes32 r;
        bytes32 s;

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        return ecrecover(message, v, r, s);
    }

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function onlyWithAdminSignature(string memory _tokenUri, address user, bytes memory signature)
        internal
        view
        returns (bool)
    {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        bytes32 message = prefixed(keccak256(abi.encodePacked(_tokenUri, user)));
        return recoverSignerFromSignature(message, signature) == ps.admin;
    }

    function _mintNFT(uint256 _tokenId, string memory _tokenUri, address user) private {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();

        require(_tokenId != 0, "Token Id cannot be 0");

        _safeMint(user, _tokenId);
        _setTokenURI(_tokenId, _tokenUri);

        ps.tokenURIs[_tokenUri] = _tokenId;
        ps.hasMinted[user] = true;
    }

    function mintNFT(uint256 _tokenId, string memory _tokenUri, bytes memory signature, uint8 tier)
        public
        _onlyWithAdminSignature(_tokenUri, msg.sender, signature)
    {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();

        require(!ps.hasMinted[msg.sender], "You have already minted an NFT");
        require(ps.tokenURIs[_tokenUri] == 0, "Token URI already exists");

        if (whitelistContract.isWhitelisted(msg.sender)) {
            whitelistContract.claim(_tokenId, msg.sender);
        }

        _mintNFT(_tokenId, _tokenUri, msg.sender);
        checkInContract.incrementPoints(msg.sender, tier);

        emit Minted(msg.sender, _tokenId);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _rerollNFT(uint256 _tokenId, address user, string memory _newtokenUri, uint256 burnTokenId) private {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        uint256 ownerTokenCount = balanceOf(user);

        if (ownerTokenCount == 0) {
            require(!ps.hasMinted[msg.sender], "You have already minted an NFT");
            require(burnTokenId == 0, "Burn token Id should be 0");
        } else {
            require(ps.tokenURIs[_newtokenUri] == 0, "Token URI already exists");
            require(ownerOf(burnTokenId) == user, "Incorrect Token Id provided for reroll");

            string memory _oldTokenUri = tokenURI(burnTokenId);
            ps.tokenURIs[_oldTokenUri] = 0;
            _burn(burnTokenId);
        }
        _mintNFT(_tokenId, _newtokenUri, user);
    }

    function rerollNFT(
        uint256 _newtokenId,
        string memory _newtokenUri,
        uint256 burnTokenId,
        bytes memory signature,
        uint8 tier
    ) public _onlyWithAdminSignature(_newtokenUri, msg.sender, signature) {
        require(checkInContract.getReRolls(msg.sender) > 0, "No rerolls available");

        _rerollNFT(_newtokenId, msg.sender, _newtokenUri, burnTokenId);
        checkInContract.incrementPoints(msg.sender, tier);
        checkInContract.decrementReRolls(msg.sender);

        emit Rerolled(msg.sender, _newtokenId, burnTokenId);
    }

    function forceTransfer(address from, address to, uint256 tokenId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token Id does not exist");
        require(ownerOf(tokenId) == from, "From address is not the owner of the token");

        _safeTransfer(from, to, tokenId, "");
    }

    function reset(address user) public onlyRole(DEFAULT_ADMIN_ROLE) {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        ps.hasMinted[user] = false;
    }

    function reset(address user, uint256 burnTokenId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();

        require(ps.hasMinted[user], "User should have already minted an NFT to reset them");
        require(balanceOf(user) > 0, "User should have already minted an NFT to reset them");
        require(ownerOf(burnTokenId) == user, "Incorrect Token Id provided for reset");

        string memory _oldTokenUri = tokenURI(burnTokenId);

        ps.tokenURIs[_oldTokenUri] = 0;
        _burn(burnTokenId);
        ps.hasMinted[user] = false;
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // View functions for storage variables

    function getAdmin() public view returns (address) {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        return ps.admin;
    }

    function getTokenURI(string memory uri) public view returns (uint256) {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        return ps.tokenURIs[uri];
    }

    function hasMinted(address user) public view returns (bool) {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        return ps.hasMinted[user];
    }
}
