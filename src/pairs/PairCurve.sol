// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/curve/ICurve.sol";
import "../interfaces/ISwappaPairV1.sol";

contract PairCurve is ISwappaPairV1 {

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
			"PairCurve: approve failed!"
		);
		ICurve swapPool = ICurve(swapPoolAddr);
		(int128 fromIdx, int128 toIdx) = getInputOutputIdx(
			swapPool,
			input,
			output
		);
		uint256 outputAmount = swapPool.exchange(
			fromIdx,
			toIdx,
			inputAmount,
			0
		);
		require(
			ERC20(output).transfer(to, outputAmount),
			"PairCurve: transfer failed!"
		);
	}

	function parseData(bytes memory data)
		private
		pure
		returns (address swapPoolAddr)
	{
		require(data.length == 20, "PairCurve: invalid data!");
		assembly {
			swapPoolAddr := mload(add(data, 20))
		}
	}

	function getOutputAmount(
		address input,
		address output,
		uint256 amountIn,
		bytes calldata data
	) external view override returns (uint256 amountOut) {
		address swapPoolAddr = parseData(data);
		ICurve swapPool = ICurve(swapPoolAddr);
		(int128 fromIdx, int128 toIdx) = getInputOutputIdx(
			swapPool,
			input,
			output
		);
		return swapPool.get_dy(fromIdx, toIdx, amountIn);
	}

    function getInputOutputIdx(
        ICurve swapPool,
        address input,
        address output
    ) public view returns (int128 fromIdx, int128 toIdx) {
        uint8 idx;
        fromIdx = toIdx = -1;
        // curve pool contain at most 4 coins
        for (idx = 0; idx < 4; idx++) {
            if (fromIdx != -1 && toIdx != -1) {
                // found coin indices
                break;
            }
            address coin = swapPool.coins(idx);
            if (coin == input) {
                fromIdx = int8(idx);
            }
            if (coin == output) {
                toIdx = int8(idx);
            }
        }
    }
}
