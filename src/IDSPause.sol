// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract IDSPause {
    function proxy() external view virtual returns (address);

    function delay() external view virtual returns (uint256);

    function scheduleTransaction(
        address,
        bytes32,
        bytes memory,
        uint256
    ) external virtual;

    function executeTransaction(
        address,
        bytes32,
        bytes memory,
        uint256
    ) external virtual;

    function abandonTransaction(
        address,
        bytes32,
        bytes memory,
        uint256
    ) external virtual;
}