// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IGlueStickERC20 {
    function applyTheGlue(address asset) external returns (address glue);
}

contract InsuranceGlueVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant YEAR = 365 days;

    address public constant OFFICIAL_GLUE_STICK_ERC20 = 0x5fEe29873DE41bb6bCAbC1E4FB0Fc4CB26a7Fd74;

    enum FeeType {
        MANAGEMENT,
        PERFORMANCE
    }

    uint16 public managementFeeBps = 200;
    uint16 public performanceFeeBps = 2000;
    uint16 public insuranceFeeShareBps = 5000;

    address public treasury;
    address public lossSink;
    address public immutable glueStick;
    address public immutable glue;

    uint256 public lastFeeAccrual;

    event GlueInitialized(address indexed glueStick, address indexed glue, address indexed stickyAsset);
    event FeeParamsUpdated(uint16 managementFeeBps, uint16 performanceFeeBps, uint16 insuranceFeeShareBps);
    event TreasuryUpdated(address indexed treasury);
    event LossSinkUpdated(address indexed lossSink);
    event ManagementFeeAccrued(uint256 elapsed, uint256 feeAssets);
    event FeeCharged(FeeType indexed feeType, uint256 totalFeeAssets, uint256 glueInsuranceAssets, uint256 treasuryAssets);
    event StrategyReported(uint256 gainRequested, uint256 gainReceived, uint256 lossAssets, uint256 performanceFeeAssets);

    error InvalidBps();
    error ZeroAddress();
    error InvalidGlueStick();
    error GlueCreationFailed();

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address treasury_,
        address lossSink_,
        address glueStickOverride_
    ) ERC20(name_, symbol_) ERC4626(asset_) Ownable(owner_) {
        if (treasury_ == address(0) || lossSink_ == address(0)) revert ZeroAddress();

        address glueStickAddress = OFFICIAL_GLUE_STICK_ERC20;
        if (block.chainid == 31337 && glueStickOverride_ != address(0)) {
            glueStickAddress = glueStickOverride_;
        } else if (glueStickOverride_ != address(0) && glueStickOverride_ != OFFICIAL_GLUE_STICK_ERC20) {
            revert InvalidGlueStick();
        }

        address glueAddress = IGlueStickERC20(glueStickAddress).applyTheGlue(address(this));
        if (glueAddress == address(0)) revert GlueCreationFailed();

        treasury = treasury_;
        lossSink = lossSink_;
        glueStick = glueStickAddress;
        glue = glueAddress;
        lastFeeAccrual = block.timestamp;

        emit GlueInitialized(glueStickAddress, glueAddress, address(this));
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

        uint256 gainReceived = 0;
        if (gainAssets > 0) {
            gainReceived = _transferFromAsset(asset(), msg.sender, address(this), gainAssets);
        }

        if (lossAssets > 0) {
            _transferAsset(asset(), lossSink, lossAssets);
        }

        uint256 performanceFeeAssets = 0;
        if (gainReceived > 0 && performanceFeeBps > 0) {
            performanceFeeAssets = _md512(gainReceived, performanceFeeBps, BPS);
            _chargeFee(performanceFeeAssets, FeeType.PERFORMANCE);
        }

        emit StrategyReported(gainAssets, gainReceived, lossAssets, performanceFeeAssets);
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

        uint256 annualizedBps = _md512(elapsed, BPS, YEAR);
        uint256 effectiveBps = _md512(managementFeeBps, annualizedBps, BPS);
        uint256 feeAssets = _md512(currentAssets, effectiveBps, BPS);

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

        uint256 glueInsuranceAssets = _md512(feeAssets, insuranceFeeShareBps, BPS);
        uint256 treasuryAssets = feeAssets - glueInsuranceAssets;

        if (glueInsuranceAssets > 0) {
            _transferAsset(asset(), glue, glueInsuranceAssets);
        }

        if (treasuryAssets > 0) {
            _transferAsset(asset(), treasury, treasuryAssets);
        }

        emit FeeCharged(feeType, feeAssets, glueInsuranceAssets, treasuryAssets);
    }

    function _transferAsset(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(token).safeTransfer(to, amount);
    }

    function _transferFromAsset(address token, address from, address to, uint256 amount) internal returns (uint256 actualReceived) {
        uint256 beforeBalance = IERC20(token).balanceOf(to);
        IERC20(token).safeTransferFrom(from, to, amount);
        uint256 afterBalance = IERC20(token).balanceOf(to);
        actualReceived = afterBalance - beforeBalance;
    }

    function _md512(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        result = Math.mulDiv(a, b, denominator);
    }
}
