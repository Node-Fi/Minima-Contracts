// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICurveAddresses {
    function get_coins(address) external view returns (address[4] memory);
    function pool_list(uint256) external view returns (address);
    function pool_count() external view returns (uint256);
    function get_pool_asset_type(address) external view returns (uint256);
    function get_fees(address) external view returns (uint256[2] memory);
}
