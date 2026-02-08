// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IGlueStickERC20 {
    function applyTheGlue(address asset) external returns (address glue);
}

contract INSToken is ERC20, Ownable {
    address public constant OFFICIAL_GLUE_STICK_ERC20 = 0x5fEe29873DE41bb6bCAbC1E4FB0Fc4CB26a7Fd74;

    address public pool;
    address public immutable glueStick;
    address public immutable glue;
    uint8 private immutable _tokenDecimals;

    error OnlyPool();
    error ZeroAddress();
    error PoolAlreadySet();
    error InvalidGlueStick();
    error GlueCreationFailed();

    event PoolSet(address indexed pool);
    event GlueLinked(address indexed glueStick, address indexed glue, address indexed token);

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address initialOwner,
        address glueStickOverride
    ) ERC20(name_, symbol_) Ownable(initialOwner) {
        address glueStickAddress = OFFICIAL_GLUE_STICK_ERC20;

        if (block.chainid == 31337 && glueStickOverride != address(0)) {
            glueStickAddress = glueStickOverride;
        } else if (glueStickOverride != address(0) && glueStickOverride != OFFICIAL_GLUE_STICK_ERC20) {
            revert InvalidGlueStick();
        }

        address glueAddress = IGlueStickERC20(glueStickAddress).applyTheGlue(address(this));
        if (glueAddress == address(0)) revert GlueCreationFailed();

        glueStick = glueStickAddress;
        glue = glueAddress;
        _tokenDecimals = decimals_;

        emit GlueLinked(glueStickAddress, glueAddress, address(this));
    }

    modifier onlyPool() {
        if (msg.sender != pool) revert OnlyPool();
        _;
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
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
