// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ISwappaPairV1} from "src/interfaces/ISwappaPairV1.sol";
import {ICeloRegistry} from "src/interfaces/mento/ICeloRegistry.sol";
import {IMentoBroker} from "src/interfaces/mento/IMentoBroker.sol";
import {IMentoExchangeProvider} from "src/interfaces/mento/IMentoExchangeProvider.sol";

import {console} from "forge-std/console.sol";

contract PairMentoV2 is ISwappaPairV1 {
    // Registry identifier for the Mento broker contract.
    string public constant BROKER_REGISTRY_IDENTIFIER = "Broker";
    address public constant CELO_REGISTRY_ADDRESS =
        0x000000000000000000000000000000000000ce10;

    // Celo registry contract.
    ICeloRegistry public immutable celoRegistry =
        ICeloRegistry(CELO_REGISTRY_ADDRESS);

    function swap(
        address input,
        address output,
        address to,
        bytes calldata data
    ) external {
        (
            address exchangeProviderAddress,
            bytes32 exchangeId,
            uint256 amountOutMin
        ) = abi.decode(data, (address, bytes32, uint256));

        // Get the broker contract.
        IMentoBroker broker = getMentoBroker();

        uint256 amountIn = IERC20(input).balanceOf(address(this));
        require(
            IERC20(input).approve(address(broker), amountIn),
            "PairMentoV2: approve failed!"
        );

        uint256 outputTokenAmountBefore = IERC20(output).balanceOf(
            address(this)
        );
        console.log(
            "Output balance of contract before: %s",
            outputTokenAmountBefore
        );

        uint256 amountOut = broker.swapIn(
            exchangeProviderAddress,
            exchangeId,
            input,
            output,
            amountIn,
            amountOutMin
        );

        console.log("Amount out after swap: %s", amountOut);

        uint256 inputTokenAmount = IERC20(input).balanceOf(address(this));
        console.log("Input balance of contract after: %s", inputTokenAmount);

        uint256 outputTokenAmount = IERC20(output).balanceOf(address(this));
        console.log("Output balance of contract after: %s", outputTokenAmount);
        require(
            IERC20(output).transfer(to, amountOut),
            "PairMentoV2: transfer failed!"
        );
    }

    function getOutputAmount(
        address input,
        address output,
        uint256 amountIn,
        bytes calldata
    ) external view returns (uint256 amountOut) {
        IMentoBroker broker = getMentoBroker();

        // Get the exchange provider address & exchange id for the specified tokens.
        (
            address exchangeProviderAddress,
            bytes32 exchangeId
        ) = getExchangeInfoForTokens(input, output, broker);

        if (exchangeProviderAddress == address(0) || exchangeId == 0) {
            return 0;
        }

        // Get a quote from the broker.
        amountOut = broker.getAmountOut(
            exchangeProviderAddress,
            exchangeId,
            input,
            output,
            amountIn
        );
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
        public
        view
        returns (address exchangeProviderAddress, bytes32 exchangeId)
    {
        // Get the list of exchange providers from the broker.
        address[] memory exchangeProviders = broker.getExchangeProviders();

        // For each exchange provider get all exchanges.
        for (uint256 i = 0; i < exchangeProviders.length; i++) {
            IMentoExchangeProvider provider = IMentoExchangeProvider(
                exchangeProviders[i]
            );

            // Get the list of exchanges for the current provider.
            IMentoExchangeProvider.Exchange[] memory exchanges = provider
                .getExchanges();

            for (uint256 j = 0; j < exchanges.length; j++) {
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

    /**
     * @notice Gets the Mento broker contract.
     */
    function getMentoBroker() public view returns (IMentoBroker broker) {
        address brokerAddress = celoRegistry.getAddressForString(
            BROKER_REGISTRY_IDENTIFIER
        );
        require(brokerAddress != address(0), "Address not found in regisry");
        broker = IMentoBroker(brokerAddress);
    }
}
