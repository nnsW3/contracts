// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract stRWA is ERC20Upgradeable, ERC20BurnableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    uint256 private constant BASE = 1e18;
    uint256 private _totalShares;
    uint256 public rewardMultiplier;
    address public RWAStaking;

    mapping(address => uint256) private _shares;
    mapping(address => mapping(address => uint256)) private _allowances;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");

    event RewardMultiplier(uint256 indexed value);

    function initialize(string memory name_, string memory symbol_, address owner) external initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Burnable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(MINTER_ROLE, owner);
        _grantRole(BURNER_ROLE, owner);
        _grantRole(UPGRADE_ROLE, owner);

        rewardMultiplier = BASE;
    }

    modifier _onlyRWAStaking() {
        require(msg.sender == RWAStaking, "stRWA: caller is not the RWAStaking contract");
        _;
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADE_ROLE) {}

    function convertToShares(uint256 amount) public view returns (uint256) {
        return (amount * BASE) / rewardMultiplier;
    }

    function convertToTokens(uint256 shares) public view returns (uint256) {
        return (shares * rewardMultiplier) / BASE;
    }

    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    function totalSupply() public view override returns (uint256) {
        return convertToTokens(_totalShares);
    }

    function sharesOf(address account) public view returns (uint256) {
        return _shares[account];
    }

    function balanceOf(address account) public view override returns (uint256) {
        return convertToTokens(sharesOf(account));
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(to != address(0), "stRWA: mint to the zero address");

        uint256 shares = convertToShares(amount);
        _totalShares += shares;

        unchecked {
            // Overflow not possible: shares + shares amount is at most totalShares + shares amount
            // which is checked above.
            _shares[to] += shares;
        }

        _afterTokenTransfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        require(from != address(0), "stRWA: burn from the zero address");

        uint256 shares = convertToShares(amount);
        uint256 accountShares = sharesOf(from);

        require(accountShares >= shares, "stRWA: burn amount exceeds balance");

        unchecked {
            _shares[from] = accountShares - shares;
            // Overflow not possible: amount <= accountShares <= totalShares.
            _totalShares -= shares;
        }

        _afterTokenTransfer(from, address(0), amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) private {
        emit Transfer(from, to, amount);
    }

    function __transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "stRWA: transfer from the zero address");
        require(to != address(0), "stRWA: transfer to the zero address");

        uint256 shares = convertToShares(amount);
        uint256 fromShares = _shares[from];

        require(fromShares >= shares, "stRWA: transfer amount exceeds balance");

        unchecked {
            _shares[from] = fromShares - shares;
            // Overflow not possible: the sum of all shares is capped by totalShares, and the sum is preserved by
            // decrementing then incrementing.
            _shares[to] += shares;
        }

        _afterTokenTransfer(from, to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();

        __transfer(owner, to, amount);

        return true;
    }

    function _setRewardMultiplier(uint256 _rewardMultiplier) private {
        require(_rewardMultiplier >= BASE, "stRWA: reward multiplier must be greater than or equal to 1");
        rewardMultiplier = _rewardMultiplier;
        emit RewardMultiplier(rewardMultiplier);
    }

    function setRewardMultiplier(uint256 _rewardMultiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRewardMultiplier(_rewardMultiplier);
    }

    function addRewardMultiplier(uint256 _rewardMultiplierIncrement) external _onlyRWAStaking {
        require(_rewardMultiplierIncrement > 0, "stRWA: reward multiplier increment must be greater than 0");
        _setRewardMultiplier(rewardMultiplier + _rewardMultiplierIncrement);
    }

    function __approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "stRWA: approve from the zero address");
        require(spender != address(0), "stRWA: approve to the zero address");

        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        address owner = _msgSender();

        __approve(owner, spender, amount);

        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function __spendAllowance(address owner, address spender, uint256 amount) private {
        uint256 currentAllowance = allowance(owner, spender);

        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "stRWA: spender allowance exceeded");

            unchecked {
                __approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();

        __spendAllowance(from, spender, amount);
        __transfer(from, to, amount);

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        address owner = _msgSender();

        __approve(owner, spender, allowance(owner, spender) + addedValue);

        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);

        require(currentAllowance >= subtractedValue, "stRWA: decreased allowance below zero");

        unchecked {
            __approve(owner, spender, currentAllowance - subtractedValue);
        }
        return true;
    }
}
