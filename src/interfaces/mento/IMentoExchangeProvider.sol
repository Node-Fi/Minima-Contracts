// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @title ExchangeProvider interface
 * @notice The IExchangeProvider interface is the interface that the Broker uses
 * to communicate with different exchange manager implementations like the BiPoolManager
 */
interface IMentoExchangeProvider {
    /**
     * @notice Exchange - a struct that's used only by UIs (frontends/CLIs)
     * in order to discover what asset swaps are possible within an
     * exchange provider.
     * It's up to the specific exchange provider to convert its internal
     * representation to this universal struct. This conversion should
     * only happen in view calls used for discovery.
     * @param exchangeId The ID of the exchange, used to initiate swaps or get quotes.
     * @param assets An array of addresses of ERC20 tokens that can be swapped.
     */
    struct Exchange {
        bytes32 exchangeId;
        address[] assets;
    }

    /**
     * @notice Get all exchanges supported by the ExchangeProvider.
     * @return exchanges An array of Exchange structs.
     */
    function getExchanges() external view returns (Exchange[] memory exchanges);
}
