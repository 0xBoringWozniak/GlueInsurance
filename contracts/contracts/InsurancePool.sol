// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IERC4626Like {
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IINSToken {
    function totalSupply() external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

contract InsurancePool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable asset;
    address public vault;
    address public insToken;

    uint256 public premiumRate;
    uint256 public deductible;
    uint256 public maxCoverage;
    uint256 public checkpointPPS;
    uint256 public lastCheckpointTs;
    uint256 public cooldown;
    uint256 public lastTriggerTs;
    uint256 public callerRewardBps;

    error ZeroAddress();
    error AlreadySet();
    error InvalidBps();
    error InvalidDeductible();
    error VaultNotSet();
    error InsTokenNotSet();
    error ZeroAmount();
    error InsufficientLiquidity();
    error CheckpointTooSoon();
    error BaselineDecrease();
    error TriggerCooldown();
    error NoLoss();
    error InvalidVaultSupply();

    event VaultSet(address indexed vault);
    event INSTokenSet(address indexed insToken);
    event PremiumRateUpdated(uint256 premiumRate);
    event ParametersUpdated(uint256 deductible, uint256 maxCoverage, uint256 cooldown, uint256 callerRewardBps);

    event Deposited(address indexed sender, address indexed receiver, uint256 assets, uint256 insMinted);
    event Withdrawn(address indexed sender, address indexed receiver, uint256 assets, uint256 insBurned);

    event PremiumPaid(address indexed vault, uint256 assets);
    event CheckpointUpdated(uint256 checkpointPPS, uint256 timestamp);
    event LossTriggered(address indexed vault, uint256 checkpointPPS, uint256 currentPPS, uint256 payout, uint256 callerReward);

    constructor(
        address asset_,
        uint256 deductible_,
        uint256 maxCoverage_,
        uint256 cooldown_,
        uint256 callerRewardBps_,
        address initialOwner
    ) Ownable(initialOwner) {
        if (asset_ == address(0)) revert ZeroAddress();
        if (deductible_ > 1e18) revert InvalidDeductible();
        if (callerRewardBps_ > 10_000) revert InvalidBps();

        asset = asset_;
        deductible = deductible_;
        maxCoverage = maxCoverage_;
        cooldown = cooldown_;
        callerRewardBps = callerRewardBps_;
    }

    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert ZeroAddress();
        if (vault != address(0)) revert AlreadySet();
        vault = vault_;
        emit VaultSet(vault_);
    }

    function setINSToken(address insToken_) external onlyOwner {
        if (insToken_ == address(0)) revert ZeroAddress();
        if (insToken != address(0)) revert AlreadySet();
        insToken = insToken_;
        emit INSTokenSet(insToken_);
    }

    function setPremiumRate(uint256 premiumRate_) external onlyOwner {
        premiumRate = premiumRate_;
        emit PremiumRateUpdated(premiumRate_);
    }

    function setParameters(uint256 deductible_, uint256 maxCoverage_, uint256 cooldown_, uint256 callerRewardBps_) external onlyOwner {
        if (deductible_ > 1e18) revert InvalidDeductible();
        if (callerRewardBps_ > 10_000) revert InvalidBps();

        deductible = deductible_;
        maxCoverage = maxCoverage_;
        cooldown = cooldown_;
        callerRewardBps = callerRewardBps_;

        emit ParametersUpdated(deductible_, maxCoverage_, cooldown_, callerRewardBps_);
    }

    function poolAssets() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function pricePerShareVault() public view returns (uint256) {
        if (vault == address(0)) revert VaultNotSet();

        uint256 vaultSupply = IERC4626Like(vault).totalSupply();
        if (vaultSupply == 0) revert InvalidVaultSupply();

        return Math.mulDiv(IERC4626Like(vault).totalAssets(), 1e18, vaultSupply);
    }

    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 insMinted) {
        if (insToken == address(0)) revert InsTokenNotSet();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets == 0) revert ZeroAmount();

        uint256 beforeAssets = poolAssets();
        uint256 totalInsSupply = IINSToken(insToken).totalSupply();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), assets);

        if (totalInsSupply == 0) {
            insMinted = assets;
        } else {
            if (beforeAssets == 0) revert InsufficientLiquidity();
            insMinted = Math.mulDiv(assets, totalInsSupply, beforeAssets);
        }

        IINSToken(insToken).mint(receiver, insMinted);

        emit Deposited(msg.sender, receiver, assets, insMinted);
    }

    function withdraw(uint256 insAmount, address receiver) external nonReentrant returns (uint256 assetsOut) {
        if (insToken == address(0)) revert InsTokenNotSet();
        if (receiver == address(0)) revert ZeroAddress();
        if (insAmount == 0) revert ZeroAmount();

        uint256 totalInsSupply = IINSToken(insToken).totalSupply();
        if (totalInsSupply == 0) revert InsufficientLiquidity();
        uint256 assetsBefore = poolAssets();

        assetsOut = Math.mulDiv(insAmount, assetsBefore, totalInsSupply);

        IINSToken(insToken).burn(msg.sender, insAmount);
        IERC20(asset).safeTransfer(receiver, assetsOut);

        emit Withdrawn(msg.sender, receiver, assetsOut, insAmount);
    }

    function onPremium(uint256 assets) external nonReentrant {
        if (msg.sender != vault) revert VaultNotSet();
        if (assets == 0) revert ZeroAmount();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), assets);

        emit PremiumPaid(msg.sender, assets);
    }

    function updateCheckpoint() external {
        if (vault == address(0)) revert VaultNotSet();
        if (block.timestamp < lastCheckpointTs + 1 days) revert CheckpointTooSoon();

        uint256 currentPPS = pricePerShareVault();
        if (checkpointPPS != 0 && currentPPS < checkpointPPS) revert BaselineDecrease();

        checkpointPPS = currentPPS;
        lastCheckpointTs = block.timestamp;

        emit CheckpointUpdated(currentPPS, block.timestamp);
    }

    function triggerLoss() external nonReentrant returns (uint256 payout, uint256 callerReward) {
        if (vault == address(0)) revert VaultNotSet();
        if (checkpointPPS == 0) revert NoLoss();
        if (block.timestamp < lastTriggerTs + cooldown) revert TriggerCooldown();

        uint256 currentPPS = pricePerShareVault();
        uint256 thresholdPPS = Math.mulDiv(checkpointPPS, (1e18 - deductible), 1e18);
        if (currentPPS >= thresholdPPS) revert NoLoss();

        uint256 lossFraction = Math.mulDiv((checkpointPPS - currentPPS), 1e18, checkpointPPS);
        uint256 payoutWanted = Math.mulDiv(IERC4626Like(vault).totalAssets(), lossFraction, 1e18);

        uint256 payoutCap = maxCoverage;
        uint256 liquid = poolAssets();
        if (payoutCap > liquid) payoutCap = liquid;

        payout = payoutWanted;
        if (payout > payoutCap) payout = payoutCap;
        if (payout == 0) revert InsufficientLiquidity();

        callerReward = Math.mulDiv(payout, callerRewardBps, 10_000);
        uint256 vaultAmount = payout - callerReward;

        lastTriggerTs = block.timestamp;

        if (vaultAmount > 0) {
            IERC20(asset).safeTransfer(vault, vaultAmount);
        }
        if (callerReward > 0) {
            IERC20(asset).safeTransfer(msg.sender, callerReward);
        }

        emit LossTriggered(vault, checkpointPPS, currentPPS, payout, callerReward);
    }
}
