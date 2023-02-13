// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILendingPoolAddressesProviderV2 {
  function getLendingPool() external view returns (address);
}
