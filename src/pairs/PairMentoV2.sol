// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../interfaces/ISwappaPairV1.sol";
import "../interfaces/mento/ICeloRegistry.sol";
import "../interfaces/mento/IMentoBroker.sol";
import "../interfaces/mento/IMentoExchangeProvider.sol";

contract PairMento is ISwappaPairV1 {
    // Registry identifier for the Mento broker contract.
    string public constant BROKER_REGISTRY_IDENTIFIER = "Broker";

    ICeloRegistry public immutable celoRegistry;

    constructor(ICeloRegistry _celoRegistry) {
        celoRegistry = _celoRegistry;
    }

    function swap(
        address input,
        address output,
        address to,
        bytes calldata data
    ) external {}

    function getOutputAmount(
        address input,
        address output,
        uint amountIn,
        bytes calldata
    ) external view returns (uint amountOut) {
        IMentoBroker broker = getMentoBroker();

        (
            address exchangeProviderAddress,
            bytes32 exchangeId
        ) = getExchangeInfoForTokens(input, output, broker);

        amountOut = broker.getAmountOut(
            exchangeProviderAddress,
            exchangeId,
            input,
            output,
            amountIn
        );
    }

    /**
     * @notice Gets the Mento broker contract.
     */
    function getMentoBroker() internal view returns (IMentoBroker broker) {
        address brokerAddress = celoRegistry.getAddressForString(
            BROKER_REGISTRY_IDENTIFIER
        );
        require(brokerAddress != address(0), "Address not found in regisry");
        broker = IMentoBroker(brokerAddress);
    }

    /**
     * @notice Gets the exchange provider address & exchange id for the specified tokens.
     * @param tokenA The first token.
     * @param tokenB The second token.
     * @param broker The Mento broker contract.
     * @return exchangeProviderAddress The address of the exchange provider.
     * @return exchangeId The exchange id that can be used to get quotes and exchange the given tokens.
     * @dev The order of tokens does not matter.
     */
    function getExchangeInfoForTokens(
        address tokenA,
        address tokenB,
        IMentoBroker broker
    )
        internal
        view
        returns (address exchangeProviderAddress, bytes32 exchangeId)
    {
        // Get the list of exchange providers from the broker.
        address[] memory exchangeProviders = broker.getExchangeProviders();

        // For each exchange provider get all exchanges.
        for (uint i = 0; i < exchangeProviders.length; i++) {
            IMentoExchangeProvider provider = IMentoExchangeProvider(
                exchangeProviders[i]
            );

            // Get the list of exchanges for the current provider.
            IMentoExchangeProvider.Exchange[] memory exchanges = provider
                .getExchanges();

            for (uint j = 0; j < exchanges.length; j++) {
                IMentoExchangeProvider.Exchange memory exchange = exchanges[j];

                // Skip exchanges that do not have exactly two tokens.
                if (exchange.assets.length != 2) {
                    continue;
                }

                // Check if the exchange has the given tokens.
                if (
                    (exchange.assets[0] == tokenA &&
                        exchange.assets[1] == tokenB) ||
                    (exchange.assets[0] == tokenB &&
                        exchange.assets[1] == tokenA)
                ) {
                    return (address(provider), exchange.exchangeId);
                }
            }
        }
    }
}
