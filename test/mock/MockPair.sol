pragma solidity 0.6.8;

import {ISwappaPairV1} from "../../src/swappa/ISwappaPairV1.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
    This mock pair will transfer out the input amount * numerator / denominator

    Mock pair, so we dont really care about overflow / underflow
 */
contract MockPair is ISwappaPairV1 {
    uint256 constant DENONMINATOR = 10**10;

    function parseData(bytes memory data)
        internal
        pure
        returns (uint256 numerator)
    {
        if (data.length != 32) {
            return DENONMINATOR;
        }

        assembly {
            numerator := mload(add(data, 32))
        }
    }

    function swap(
        address input,
        address output,
        address to,
        bytes calldata data
    ) external override {
        uint256 inputAmount = ERC20(input).balanceOf(address(this));
        uint256 numerator = parseData(data);
        uint256 outputAmount = (inputAmount * numerator) / DENONMINATOR;

        ERC20(output).transfer(to, outputAmount);
    }

    function getOutputAmount(
        address,
        address,
        uint256 amountIn,
        bytes calldata data
    ) external view override returns (uint256 amountOut) {
        uint256 numerator = parseData(data);
        amountOut = (amountIn * numerator) / DENONMINATOR;
    }
}
