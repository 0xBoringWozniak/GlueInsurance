// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockGlue {
    using SafeERC20 for IERC20;

    address public immutable stickyAsset;

    constructor(address stickyAsset_) {
        stickyAsset = stickyAsset_;
    }

    function unglue(address[] calldata collaterals, uint256 amount, address recipient)
        external
        returns (uint256 supplyDelta, uint256 realAmount, uint256 beforeTotalSupply, uint256 afterTotalSupply)
    {
        require(collaterals.length > 0, "no collateral");
        require(amount > 0, "zero amount");

        beforeTotalSupply = IERC20(stickyAsset).totalSupply();
        IERC20(stickyAsset).safeTransferFrom(msg.sender, address(this), amount);

        realAmount = amount;
        if (recipient == address(0)) {
            recipient = msg.sender;
        }

        for (uint256 i = 0; i < collaterals.length; i++) {
            uint256 bal = IERC20(collaterals[i]).balanceOf(address(this));
            uint256 share = beforeTotalSupply == 0 ? 0 : (bal * amount * 999) / (beforeTotalSupply * 1000);
            if (share > 0) {
                IERC20(collaterals[i]).safeTransfer(recipient, share);
            }
        }

        afterTotalSupply = beforeTotalSupply > amount ? beforeTotalSupply - amount : 0;
        supplyDelta = beforeTotalSupply == 0 ? 0 : (amount * 1e18) / beforeTotalSupply;
    }
}
