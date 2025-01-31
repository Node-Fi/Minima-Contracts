// SPDX-License-Identifier: MIT
pragma solidity 0.6.8;
pragma experimental ABIEncoderV2;

import "@openzeppelin06/contracts/math/SafeMath.sol";
import "@openzeppelin06/contracts/token/ERC20/ERC20.sol";
import "../interfaces/algebra/IAlgebraPool.sol";
import "../interfaces/algebra/callback/IAlgebraSwapCallback.sol";
import "../interfaces/algebra/utils/AlgQuoter.sol";
import "../interfaces/uniswap/SafeCast.sol";
import "../interfaces/algebra/utils/AlgTickLens.sol";
import "../interfaces/uniswap/TickMath.sol";
import "../interfaces/ISwappaPairV16.sol";


contract PairAlgebra is ISwappaPairV1, IAlgebraSwapCallback {
    using SafeMath for uint256;
    using SafeCast for uint256;

    function swap(
        address input,
        address output,
        address to,
        bytes calldata data
    ) external override {
        address pairAddr = parseData(data);
        uint256 inputAmount = ERC20(input).balanceOf(address(this));
        IAlgebraPool pair = IAlgebraPool(pairAddr);
        bool zeroForOne = pair.token0() == input;
        // calling swap will trigger the uniswapV3SwapCallback
        pair.swap(
            to,
            zeroForOne,
            inputAmount.toInt256(),
            zeroForOne
                ? TickMath.MIN_SQRT_RATIO + 1
                : TickMath.MAX_SQRT_RATIO - 1,
            new bytes(0)
        );
    }

    function algebraSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external override {
        ERC20 token;
        uint256 amount;
        if (amount0Delta > 0) {
            amount = uint256(amount0Delta);
            token = ERC20(IAlgebraPool(msg.sender).token0());
        } else if (amount1Delta > 0) {
            amount = uint256(amount1Delta);
            token = ERC20(IAlgebraPool(msg.sender).token1());
        }
        require(
            token.transfer(msg.sender, amount),
            "PairAlgebra: transfer failed!"
        );
    }

    function parseData(bytes memory data)
        private
        pure
        returns (address pairAddr)
    {
        require(data.length == 20, "PairAlgebra: invalid data!");
        assembly {
            pairAddr := mload(add(data, 20))
        }
    }

    function getOutputAmount(
        address input,
        address output,
        uint256 amountIn,
        bytes calldata data
    ) external view override returns (uint256 amountOut) {
        address pairAddr = parseData(data);
        IAlgebraPool pair = IAlgebraPool(pairAddr);
        bool zeroForOne = pair.token0() == input;
        // amount0, amount1 are delta of the pair reserves
        (int256 amount0, int256 amount1) = AlgQuoter.quote(
            pair,
            zeroForOne,
            amountIn.toInt256(),
            zeroForOne
                ? TickMath.MIN_SQRT_RATIO + 1
                : TickMath.MAX_SQRT_RATIO - 1
        );
        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    function getInputAmount(
        address input,
        address output,
        uint256 amountOut,
        bytes calldata data
    ) external view returns (uint256 amountIn) {
        address pairAddr = parseData(data);
        IAlgebraPool pair = IAlgebraPool(pairAddr);
        bool zeroForOne = pair.token0() == input;
        // amount0, amount1 are delta of the pair reserves
        (int256 amount0, int256 amount1) = AlgQuoter.quote(
            pair,
            zeroForOne,
            -amountOut.toInt256(),
            zeroForOne
                ? TickMath.MIN_SQRT_RATIO + 1
                : TickMath.MAX_SQRT_RATIO - 1
        );
        return uint256(zeroForOne ? amount0 : amount1);
    }

    function getSpotTicks(IAlgebraPool pool)
        public
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            AlgTickLens.PopulatedTick[] memory populatedTicksTwiceAbove,
            AlgTickLens.PopulatedTick[] memory populatedTicksAbove,
            AlgTickLens.PopulatedTick[] memory populatedTicksSpot,
            AlgTickLens.PopulatedTick[] memory populatedTicksBelow,
            AlgTickLens.PopulatedTick[] memory populatedTicksTwiceBelow
        )
    {
        return AlgTickLens.getSpotTicks(pool);
    }

    function getPopulatedTicksInWord(IAlgebraPool pool, int16 tickBitmapIndex)
        public
        view
        returns (AlgTickLens.PopulatedTick[] memory populatedTicks)
    {
        return AlgTickLens.getPopulatedTicksInWord(pool, tickBitmapIndex);
    }

    function recoverERC20(ERC20 token) public {
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }
}