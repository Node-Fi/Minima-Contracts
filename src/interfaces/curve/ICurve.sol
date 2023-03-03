// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICurve {
    function A() external view returns (uint256);
    
    function A_precise() external view returns (uint256);

    function fee() external view returns (uint256);

    function coins(uint256 i) external view returns (address);

    function balances(uint256 i) external view returns (uint256);

    function get_balances() external view returns (uint256[4] memory);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    function get_virtual_price() external view returns (uint256);
}
