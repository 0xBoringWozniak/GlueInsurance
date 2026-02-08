// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract InsurancePool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    address public vault;

    uint256 public totalStaked;
    uint256 public accPremiumPerShare;

    mapping(address => uint256) public stakeOf;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public claimable;

    event VaultUpdated(address indexed newVault);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event PremiumNotified(uint256 amount, uint256 accPremiumPerShare);
    event Claimed(address indexed user, uint256 amount);

    error OnlyVault();
    error ZeroAmount();
    error InsufficientStake();

    constructor(address asset_, address initialOwner) Ownable(initialOwner) {
        asset = IERC20(asset_);
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    function setVault(address newVault) external onlyOwner {
        vault = newVault;
        emit VaultUpdated(newVault);
    }

    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _accrue(msg.sender);

        asset.safeTransferFrom(msg.sender, address(this), amount);
        totalStaked += amount;
        stakeOf[msg.sender] += amount;
        rewardDebt[msg.sender] = (stakeOf[msg.sender] * accPremiumPerShare) / 1e18;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (stakeOf[msg.sender] < amount) revert InsufficientStake();

        _accrue(msg.sender);

        stakeOf[msg.sender] -= amount;
        totalStaked -= amount;
        rewardDebt[msg.sender] = (stakeOf[msg.sender] * accPremiumPerShare) / 1e18;

        asset.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function notifyPremium(uint256 amount) external onlyVault {
        if (amount == 0 || totalStaked == 0) return;

        accPremiumPerShare += (amount * 1e18) / totalStaked;
        emit PremiumNotified(amount, accPremiumPerShare);
    }

    function claim() external nonReentrant returns (uint256 amount) {
        _accrue(msg.sender);

        amount = claimable[msg.sender];
        if (amount == 0) revert ZeroAmount();

        claimable[msg.sender] = 0;
        asset.safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    function pendingPremium(address user) external view returns (uint256) {
        uint256 accumulated = (stakeOf[user] * accPremiumPerShare) / 1e18;
        return claimable[user] + accumulated - rewardDebt[user];
    }

    function _accrue(address user) internal {
        uint256 accumulated = (stakeOf[user] * accPremiumPerShare) / 1e18;
        uint256 debt = rewardDebt[user];
        if (accumulated > debt) {
            claimable[user] += accumulated - debt;
        }
        rewardDebt[user] = accumulated;
    }
}
