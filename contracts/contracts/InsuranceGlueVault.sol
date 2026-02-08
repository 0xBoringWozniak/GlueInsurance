// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {InsurancePool} from "./InsurancePool.sol";

contract InsuranceGlueVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant YEAR = 365 days;

    enum FeeType {
        MANAGEMENT,
        PERFORMANCE
    }

    uint16 public managementFeeBps = 200;
    uint16 public performanceFeeBps = 2000;
    uint16 public insuranceFeeShareBps = 5000;

    address public treasury;
    address public lossSink;
    InsurancePool public immutable insurancePool;

    uint256 public lastFeeAccrual;

    event FeeParamsUpdated(uint16 managementFeeBps, uint16 performanceFeeBps, uint16 insuranceFeeShareBps);
    event TreasuryUpdated(address indexed treasury);
    event LossSinkUpdated(address indexed lossSink);
    event ManagementFeeAccrued(uint256 elapsed, uint256 feeAssets);
    event FeeCharged(FeeType indexed feeType, uint256 totalFeeAssets, uint256 insuranceAssets, uint256 treasuryAssets);
    event StrategyReported(uint256 gainAssets, uint256 lossAssets, uint256 performanceFeeAssets);

    error InvalidBps();
    error ZeroAddress();

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address treasury_,
        address lossSink_,
        InsurancePool insurancePool_
    ) ERC20(name_, symbol_) ERC4626(asset_) Ownable(owner_) {
        if (treasury_ == address(0) || lossSink_ == address(0) || address(insurancePool_) == address(0)) revert ZeroAddress();

        treasury = treasury_;
        lossSink = lossSink_;
        insurancePool = insurancePool_;
        lastFeeAccrual = block.timestamp;
    }

    function setFeeParams(uint16 managementFeeBps_, uint16 performanceFeeBps_, uint16 insuranceFeeShareBps_) external onlyOwner {
        if (managementFeeBps_ > BPS || performanceFeeBps_ > BPS || insuranceFeeShareBps_ > BPS) revert InvalidBps();

        _accrueManagementFee();

        managementFeeBps = managementFeeBps_;
        performanceFeeBps = performanceFeeBps_;
        insuranceFeeShareBps = insuranceFeeShareBps_;

        emit FeeParamsUpdated(managementFeeBps_, performanceFeeBps_, insuranceFeeShareBps_);
    }

    function setTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function setLossSink(address lossSink_) external onlyOwner {
        if (lossSink_ == address(0)) revert ZeroAddress();
        lossSink = lossSink_;
        emit LossSinkUpdated(lossSink_);
    }

    function accrueFees() external {
        _accrueManagementFee();
    }

    function report(uint256 gainAssets, uint256 lossAssets) external onlyOwner nonReentrant {
        _accrueManagementFee();

        if (gainAssets > 0) {
            IERC20(asset()).safeTransferFrom(msg.sender, address(this), gainAssets);
        }
        if (lossAssets > 0) {
            IERC20(asset()).safeTransfer(lossSink, lossAssets);
        }

        uint256 performanceFeeAssets = 0;
        if (gainAssets > 0 && performanceFeeBps > 0) {
            performanceFeeAssets = (gainAssets * performanceFeeBps) / BPS;
            _chargeFee(performanceFeeAssets, FeeType.PERFORMANCE);
        }

        emit StrategyReported(gainAssets, lossAssets, performanceFeeAssets);
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        _accrueManagementFee();
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256) {
        _accrueManagementFee();
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        _accrueManagementFee();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        _accrueManagementFee();
        return super.redeem(shares, receiver, owner);
    }

    function _accrueManagementFee() internal {
        uint256 elapsed = block.timestamp - lastFeeAccrual;
        if (elapsed == 0 || managementFeeBps == 0) {
            lastFeeAccrual = block.timestamp;
            return;
        }

        uint256 currentAssets = totalAssets();
        if (currentAssets == 0) {
            lastFeeAccrual = block.timestamp;
            return;
        }

        uint256 feeAssets = (currentAssets * managementFeeBps * elapsed) / (YEAR * BPS);
        lastFeeAccrual = block.timestamp;

        emit ManagementFeeAccrued(elapsed, feeAssets);
        _chargeFee(feeAssets, FeeType.MANAGEMENT);
    }

    function _chargeFee(uint256 feeAssets, FeeType feeType) internal {
        if (feeAssets == 0) return;

        uint256 liquidAssets = IERC20(asset()).balanceOf(address(this));
        if (feeAssets > liquidAssets) {
            feeAssets = liquidAssets;
        }
        if (feeAssets == 0) return;

        uint256 insuranceAssets = (feeAssets * insuranceFeeShareBps) / BPS;
        uint256 treasuryAssets = feeAssets - insuranceAssets;

        if (insuranceAssets > 0) {
            IERC20(asset()).safeTransfer(address(insurancePool), insuranceAssets);
            insurancePool.notifyPremium(insuranceAssets);
        }

        if (treasuryAssets > 0) {
            IERC20(asset()).safeTransfer(treasury, treasuryAssets);
        }

        emit FeeCharged(feeType, feeAssets, insuranceAssets, treasuryAssets);
    }
}
