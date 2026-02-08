// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract INSToken is ERC20, Ownable {
    address public pool;

    error OnlyPool();
    error ZeroAddress();
    error PoolAlreadySet();

    event PoolSet(address indexed pool);

    constructor(string memory name_, string memory symbol_, address initialOwner) ERC20(name_, symbol_) Ownable(initialOwner) {}

    modifier onlyPool() {
        if (msg.sender != pool) revert OnlyPool();
        _;
    }

    function setPool(address pool_) external onlyOwner {
        if (pool == address(0)) {
            if (pool_ == address(0)) revert ZeroAddress();
            pool = pool_;
            emit PoolSet(pool_);
            return;
        }
        revert PoolAlreadySet();
    }

    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyPool {
        _burn(from, amount);
    }
}
