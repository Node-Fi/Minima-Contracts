// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/INative.sol";
import "../interfaces/stader/IMaticX.sol";
import "../interfaces/ISwappaPairV1.sol";

contract PairStader is ISwappaPairV1 {

	function swap(
		address input,
		address output,
		address to,
		bytes calldata data
	) external override {
		(address poolAddr) = parseData(data);
		uint256 inputAmount = ERC20(input).balanceOf(address(this));
		require(inputAmount > 0, "Stader: deposit amount must be greater than 0.");
        //Wrapped -> Native
        INative(input).withdraw(inputAmount);
		
        // Native -> MaticX.
        IMaticX(poolAddr).swapMaticForMaticXViaInstantPool{value: inputAmount}();
        uint256 maticXBal = ERC20(output).balanceOf(address(this));
        ERC20(output).approve(to, maticXBal);
        ERC20(output).transfer(to, maticXBal);
	}

	function parseData(bytes memory data) private pure returns (address poolAddr) {
		require(data.length == 20, "Stader: invalid data!");
		assembly {
			poolAddr := mload(add(data, 20))
		}
	}

	function getOutputAmount(
		address input,
		address output,
		uint amountIn,
		bytes calldata data
	) external view override returns (uint amountOut) {
		return amountIn;
	}

	receive() external payable {}
}