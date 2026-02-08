// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockGlue} from "./MockGlue.sol";

contract MockGlueStick {
    mapping(address => address) public glueByAsset;

    event GlueCreated(address indexed asset, address indexed glue);

    function applyTheGlue(address asset) external returns (address glue) {
        glue = glueByAsset[asset];
        if (glue == address(0)) {
            glue = address(new MockGlue(asset));
            glueByAsset[asset] = glue;
            emit GlueCreated(asset, glue);
        }
    }
}
