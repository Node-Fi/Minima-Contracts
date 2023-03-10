// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @title The Celo registry contract interface
 */
interface ICeloRegistry {
    /**
     * @notice Returns the contract address for the specified identifier from the Celo registry.
     * @param identifier The identifier to lookup.
     * @return The address associated with the given identifier.
     */
    function getAddressForString(
        string calldata identifier
    ) external view returns (address);
}
