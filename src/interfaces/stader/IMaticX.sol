// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IMaticX {
    //deposit
    function swapMaticForMaticXViaInstantPool() external payable;
    function convertMaticToMaticX(uint256) external view returns (uint256, uint256, uint256);
}

