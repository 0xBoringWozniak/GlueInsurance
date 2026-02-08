// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract InsuranceRegistry {
    mapping(address => address) public vaultToPool;

    error ZeroAddress();
    error AlreadyRegistered();

    event VaultRegistered(address indexed vault, address indexed pool);

    function registerVault(address vault, address pool) external {
        if (vault == address(0) || pool == address(0)) revert ZeroAddress();
        if (vaultToPool[vault] != address(0)) revert AlreadyRegistered();

        vaultToPool[vault] = pool;
        emit VaultRegistered(vault, pool);
    }

    function getPool(address vault) external view returns (address) {
        return vaultToPool[vault];
    }
}
