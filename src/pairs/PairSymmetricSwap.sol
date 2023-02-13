// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin08/contracts/utils/math/SafeMath.sol";
import "@openzeppelin08/contracts/token/ERC20/ERC20.sol";
import "../interfaces/symmetric/ISymmetricSwap.sol";
import "../interfaces/ISwappaPairV1.sol";

contract PairSymmetricSwap is ISwappaPairV1 {
    using SafeMath for uint256;

    function swap(
        address input,
        address output,
        address to,
        bytes calldata data
    ) external override {
        address swapPoolAddr = parseData(data);
        uint256 inputAmount = ERC20(input).balanceOf(address(this));
        require(
            ERC20(input).approve(swapPoolAddr, inputAmount),
            "PairSymmetricSwap: approve failed!"
        );
        ISymmetricSwap(swapPoolAddr).swap(input, output, inputAmount);
        require(
            ERC20(output).transfer(to, inputAmount),
            "PairSymmetricSwap: transfer failed!"
        );
    }

    function parseData(bytes memory data)
        private
        pure
        returns (address swapPoolAddr)
    {
        require(data.length == 20, "PairSymmetricSwap: invalid data!");
        assembly {
            swapPoolAddr := mload(add(data, 20))
        }
    }

    function getOutputAmount(
        address,
        address output,
        uint256 amountIn,
        bytes calldata data
    ) external view override returns (uint256 amountOut) {
        // no fees are taken if there's enough output token
        if (ERC20(output).balanceOf(parseData(data)) >= amountIn) {
            amountOut = amountIn;
        }
    }
}
