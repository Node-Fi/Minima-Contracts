// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/*
 * @title Mento Broker Interface for trader functions
 * @notice The broker is responsible for executing swaps and providing quotes.
 */
interface IMentoBroker {
    /**
     * @notice Calculate amountOut of tokenOut received for a given amountIn of tokenIn.
     * @param exchangeProvider the address of the exchange provider for the pair.
     * @param exchangeId The id of the exchange to use.
     * @param tokenIn The token to be sold.
     * @param tokenOut The token to be bought.
     * @param amountIn The amount of tokenIn to be sold.
     * @return amountOut The amount of tokenOut to be bought.
     */
    function getAmountOut(
        address exchangeProvider,
        bytes32 exchangeId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /**
     * @notice Execute a token swap with fixed amountIn.
     * @param exchangeProvider the address of the exchange provider for the pair.
     * @param exchangeId The id of the exchange to use.
     * @param tokenIn The token to be sold.
     * @param tokenOut The token to be bought.
     * @param amountIn The amount of tokenIn to be sold.
     * @param amountOutMin Minimum amountOut to be received - controls slippage.
     * @return amountOut The amount of tokenOut to be bought.
     */
    function swapIn(
        address exchangeProvider,
        bytes32 exchangeId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256 amountOut);

    /**
     * @notice Get the list of registered exchange providers.
     * @dev This can be used by UI or clients to discover all pairs.
     * @return exchangeProviders the addresses of all exchange providers.
     */
    function getExchangeProviders()
        external
        view
        returns (address[] memory exchangeProviders);
}
