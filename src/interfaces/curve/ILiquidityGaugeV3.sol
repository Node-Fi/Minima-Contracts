// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILiquidityGaugeV3 is IERC20 {
    function deposit(uint256 value, address recipient) external;

    function withdraw(uint256 value) external;
}