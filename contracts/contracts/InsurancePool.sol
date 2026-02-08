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

interface IGlueERC20Like {
    function unglue(address[] calldata collaterals, uint256 amount, address recipient)
        external
        returns (uint256 supplyDelta, uint256 realAmount, uint256 beforeTotalSupply, uint256 afterTotalSupply);
}

interface IINSToken {
    function totalSupply() external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function glue() external view returns (address);
}

contract InsurancePool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant GLUE_PROTOCOL_FEE = 1e15; // 0.1%

    address public immutable asset;
    address public vault;
    address public insToken;
    address public insGlue;

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
    error GlueNotSet();
    error ZeroAmount();
    error CheckpointTooSoon();
    error BaselineDecrease();
    error TriggerCooldown();
    error NoLoss();
    error InvalidVaultSupply();
    error InsufficientLiquidity();

    event VaultSet(address indexed vault);
    event INSTokenSet(address indexed insToken, address indexed insGlue);
    event PremiumRateUpdated(uint256 premiumRate);
    event ParametersUpdated(uint256 deductible, uint256 maxCoverage, uint256 cooldown, uint256 callerRewardBps);

    event Deposited(address indexed sender, address indexed receiver, uint256 assets, uint256 insMinted);
    event Redeemed(address indexed sender, address indexed receiver, uint256 insBurned, uint256 assetsOut);

    event PremiumPaid(address indexed vault, address indexed insGlue, uint256 assets);
    event CheckpointUpdated(uint256 checkpointPPS, uint256 timestamp);
    event LossTriggered(address indexed vault, uint256 checkpointPPS, uint256 currentPPS, uint256 payout, uint256 callerReward, uint256 insMinted, uint256 insBurned);

    constructor(
        address asset_,
        uint256 deductible_,
        uint256 maxCoverage_,
        uint256 cooldown_,
        uint256 callerRewardBps_,
        address initialOwner
    ) Ownable(initialOwner) {
        if (asset_ == address(0)) revert ZeroAddress();
        if (deductible_ > PRECISION) revert InvalidDeductible();
        if (callerRewardBps_ > BPS) revert InvalidBps();

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
        insGlue = IINSToken(insToken_).glue();
        if (insGlue == address(0)) revert GlueNotSet();

        IERC20(insToken_).forceApprove(insGlue, type(uint256).max);

        emit INSTokenSet(insToken_, insGlue);
    }

    function setPremiumRate(uint256 premiumRate_) external onlyOwner {
        premiumRate = premiumRate_;
        emit PremiumRateUpdated(premiumRate_);
    }

    function setParameters(uint256 deductible_, uint256 maxCoverage_, uint256 cooldown_, uint256 callerRewardBps_) external onlyOwner {
        if (deductible_ > PRECISION) revert InvalidDeductible();
        if (callerRewardBps_ > BPS) revert InvalidBps();

        deductible = deductible_;
        maxCoverage = maxCoverage_;
        cooldown = cooldown_;
        callerRewardBps = callerRewardBps_;

        emit ParametersUpdated(deductible_, maxCoverage_, cooldown_, callerRewardBps_);
    }

    function poolAssets() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function insGlueCollateral() public view returns (uint256) {
        if (insGlue == address(0)) return 0;
        return IERC20(asset).balanceOf(insGlue);
    }

    function pricePerShareVault() public view returns (uint256) {
        if (vault == address(0)) revert VaultNotSet();

        uint256 vaultSupply = IERC4626Like(vault).totalSupply();
        if (vaultSupply == 0) revert InvalidVaultSupply();

        return _md512(IERC4626Like(vault).totalAssets(), PRECISION, vaultSupply);
    }

    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 insMinted) {
        if (insToken == address(0)) revert InsTokenNotSet();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets == 0) revert ZeroAmount();

        uint256 supplyBefore = IINSToken(insToken).totalSupply();
        uint256 collateralBefore = insGlueCollateral();

        _transferFromAsset(asset, msg.sender, insGlue, assets);

        if (supplyBefore == 0 || collateralBefore == 0) {
            insMinted = assets;
        } else {
            insMinted = _md512(assets, supplyBefore, collateralBefore);
        }

        IINSToken(insToken).mint(receiver, insMinted);

        emit Deposited(msg.sender, receiver, assets, insMinted);
    }

    function redeem(uint256 insAmount, address receiver) external nonReentrant returns (uint256 assetsOut) {
        if (insToken == address(0)) revert InsTokenNotSet();
        if (receiver == address(0)) revert ZeroAddress();
        if (insAmount == 0) revert ZeroAmount();

        _transferFromAsset(insToken, msg.sender, address(this), insAmount);
        assetsOut = _unglueTo(asset, insAmount, receiver);

        emit Redeemed(msg.sender, receiver, insAmount, assetsOut);
    }

    function onPremium(uint256 assets) external nonReentrant {
        if (msg.sender != vault) revert VaultNotSet();
        if (insGlue == address(0)) revert GlueNotSet();
        if (assets == 0) revert ZeroAmount();

        _transferFromAsset(asset, msg.sender, insGlue, assets);

        emit PremiumPaid(msg.sender, insGlue, assets);
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

    function triggerLoss() external nonReentrant returns (uint256 payout, uint256 callerReward, uint256 insMinted, uint256 insBurned) {
        if (vault == address(0)) revert VaultNotSet();
        if (insToken == address(0)) revert InsTokenNotSet();
        if (checkpointPPS == 0) revert NoLoss();
        if (block.timestamp < lastTriggerTs + cooldown) revert TriggerCooldown();

        uint256 currentPPS = pricePerShareVault();
        uint256 thresholdPPS = _md512(checkpointPPS, (PRECISION - deductible), PRECISION);
        if (currentPPS >= thresholdPPS) revert NoLoss();

        uint256 lossFraction = _md512((checkpointPPS - currentPPS), PRECISION, checkpointPPS);
        uint256 payoutWanted = _md512(IERC4626Like(vault).totalAssets(), lossFraction, PRECISION);

        uint256 available = _maxAvailableFromGlue();
        payout = payoutWanted;
        if (payout > maxCoverage) payout = maxCoverage;
        if (payout > available) payout = available;
        if (payout == 0) revert InsufficientLiquidity();

        insMinted = _insNeededForPayout(payout);
        IINSToken(insToken).mint(address(this), insMinted);

        insBurned = insMinted;
        uint256 received = _unglueTo(asset, insBurned, address(this));

        callerReward = _md512(received, callerRewardBps, BPS);
        uint256 vaultAmount = received - callerReward;

        lastTriggerTs = block.timestamp;

        if (vaultAmount > 0) _transferAsset(asset, vault, vaultAmount);
        if (callerReward > 0) _transferAsset(asset, msg.sender, callerReward);

        emit LossTriggered(vault, checkpointPPS, currentPPS, received, callerReward, insMinted, insBurned);

        return (received, callerReward, insMinted, insBurned);
    }

    function _maxAvailableFromGlue() internal view returns (uint256) {
        uint256 glueBal = insGlueCollateral();
        return _md512(glueBal, (PRECISION - GLUE_PROTOCOL_FEE), PRECISION);
    }

    function _insNeededForPayout(uint256 payout) internal view returns (uint256 insAmount) {
        uint256 insSupply = IINSToken(insToken).totalSupply();
        uint256 glueBal = insGlueCollateral();

        if (insSupply == 0 || glueBal == 0) revert InsufficientLiquidity();

        uint256 adjustedCollateral = _md512(glueBal, (PRECISION - GLUE_PROTOCOL_FEE), PRECISION);
        insAmount = _md512Up(payout, insSupply, adjustedCollateral);
    }

    function _unglueTo(address collateral, uint256 insAmount, address recipient) internal returns (uint256 received) {
        if (insAmount == 0) return 0;

        uint256 beforeBal = IERC20(collateral).balanceOf(recipient);
        address[] memory collaterals = new address[](1);
        collaterals[0] = collateral;

        IGlueERC20Like(insGlue).unglue(collaterals, insAmount, recipient);

        uint256 afterBal = IERC20(collateral).balanceOf(recipient);
        received = afterBal - beforeBal;
    }

    function _transferAsset(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(token).safeTransfer(to, amount);
    }

    function _transferFromAsset(address token, address from, address to, uint256 amount) internal returns (uint256 actualReceived) {
        uint256 beforeBal = IERC20(token).balanceOf(to);
        IERC20(token).safeTransferFrom(from, to, amount);
        uint256 afterBal = IERC20(token).balanceOf(to);
        actualReceived = afterBal - beforeBal;
    }

    function _md512(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        return Math.mulDiv(a, b, denominator);
    }

    function _md512Up(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        return Math.mulDiv(a, b, denominator, Math.Rounding.Ceil);
    }
}
