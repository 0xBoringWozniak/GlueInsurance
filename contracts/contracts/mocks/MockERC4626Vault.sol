// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IInsurancePoolPremium {
    function onPremium(uint256 assets) external;
}

contract MockERC4626Vault {
    using SafeERC20 for IERC20;

    address public immutable asset;

    uint256 private _totalAssets;
    uint256 private _totalSupply;

    constructor(address asset_) {
        asset = asset_;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function setTotalAssets(uint256 value) external {
        _totalAssets = value;
    }

    function setTotalSupply(uint256 value) external {
        _totalSupply = value;
    }

    function payPremiumToPool(address pool, uint256 amount) external {
        IERC20(asset).forceApprove(pool, amount);
        IInsurancePoolPremium(pool).onPremium(amount);
    }
}
