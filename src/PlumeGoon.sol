// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin-contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin-contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin-contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin-contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin-contracts/access/AccessControl.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "./interfaces/IWhitelist.sol";
import "./interfaces/ICheckin.sol";

contract PlumeGoon is ERC721URIStorage, ERC721Enumerable, ERC721Pausable, AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    address public admin;

    IWhitelist public whitelistContract;
    ICheckIn public checkInContract;

    mapping(string => uint256) private _tokenURIs; // to ensure token uri is unique i.e same nft cannot be claimed by another user
    mapping(address => bool) public _hasMinted;

    event Minted(address indexed user, uint256 tokenId);
    event Rerolled(address indexed user, uint256 newtokenId, uint256 burnTokenId);

    constructor(
        string memory name,
        string memory symbol,
        address whitelistAddress,
        address checkInAddress,
        address pauser,
        address minter
    ) ERC721(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(MINTER_ROLE, minter);
        whitelistContract = IWhitelist(whitelistAddress);
        checkInContract = ICheckIn(checkInAddress);
        admin = msg.sender;
    }

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
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
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
        bytes32 message = prefixed(keccak256(abi.encodePacked(_tokenUri, user)));
        return recoverSignerFromSignature(message, signature) == admin;
    }

    function _mintNFT(uint256 _tokenId, string memory _tokenUri, address user) private {
        require(_tokenId != 0, "Token Id cannot be 0");
        _safeMint(user, _tokenId);
        _setTokenURI(_tokenId, _tokenUri);
        _tokenURIs[_tokenUri] = _tokenId;
        _hasMinted[user] = true;
    }

    function mintNFT(uint256 _tokenId, string memory _tokenUri, bytes memory signature, uint8 tier)
        public
        _onlyWithAdminSignature(_tokenUri, msg.sender, signature)
    {
        require(!_hasMinted[msg.sender], "You have already minted an NFT");
        require(_tokenURIs[_tokenUri] == 0, "Token URI already exists");

        if (whitelistContract.isWhitelisted(msg.sender)) {
            whitelistContract.claim(_tokenId, msg.sender);
        }

        _mintNFT(_tokenId, _tokenUri, msg.sender);
        checkInContract.incrementPoints(_tokenUri, msg.sender, signature, tier);
        emit Minted(msg.sender, _tokenId);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _rerollNFT(uint256 _tokenId, address user, string memory _newtokenUri, uint256 burnTokenId) private {
        uint256 ownerTokenCount = balanceOf(user);
        if (ownerTokenCount == 0) {
            require(!_hasMinted[msg.sender], "You have already minted an NFT");
            require(burnTokenId == 0, "Burn token Id should be 0");
        } else {
            require(_tokenURIs[_newtokenUri] == 0, "Token URI already exists");
            require(ownerOf(burnTokenId) == user, "Incorrect Token Id provided for reroll");

            string memory _oldTokenUri = tokenURI(burnTokenId);
            _tokenURIs[_oldTokenUri] = 0;
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
        checkInContract.incrementPoints(_newtokenUri, msg.sender, signature, tier);
        emit Rerolled(msg.sender, _newtokenId, burnTokenId);
    }

    function forceTransfer(address from, address to, uint256 tokenId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token Id does not exist");
        require(ownerOf(tokenId) == from, "From address is not the owner of the token");
        _safeTransfer(from, to, tokenId, "");
    }

    function reset(address user) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _hasMinted[user] = false;
    }

    function reset(address user, uint256 burnTokenId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_hasMinted[user], "User should have already minted an NFT to reset them");
        require(balanceOf(user) > 0, "User should have already minted an NFT to reset them");
        require(ownerOf(burnTokenId) == user, "Incorrect Token Id provided for reset");
        string memory _oldTokenUri = tokenURI(burnTokenId);
        _tokenURIs[_oldTokenUri] = 0;
        _burn(burnTokenId);
        _hasMinted[user] = false;
    }

    function hasMinted(address user) public view returns (bool) {
        return _hasMinted[user];
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
