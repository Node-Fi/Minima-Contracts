// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// solhint-disable no-console

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {PairMentoV2} from "src/pairs/PairMentoV2.sol";

contract PairMentoV2Test is Test {
    string public baklavaRpcUrl = vm.envString("BAKLAVA_RPC_URL");

    // Baklava contract addresses
    address public CELO_ADDRESS = 0xdDc9bE57f553fe75752D61606B94CBD7e0264eF8;
    address public CUSD_ADDRESS = 0x62492A644A588FD904270BeD06ad52B9abfEA1aE;

    PairMentoV2 public pairMentoV2;

    function setUp() public {
        vm.createSelectFork(baklavaRpcUrl);

        pairMentoV2 = new PairMentoV2();
    }

    function testGetOutputAmount() public {
        uint256 outputAmount = pairMentoV2.getOutputAmount(
            CELO_ADDRESS,
            CUSD_ADDRESS,
            1 ether,
            ""
        );

        assertTrue(outputAmount > 0);
    }

    function testGetOutputAmountWithNonMentoTokensReturnsZero() public {
        uint256 outputAmount = pairMentoV2.getOutputAmount(
            address(0),
            makeAddr("SomeAddress"),
            1 ether,
            ""
        );

        assertEq(outputAmount, 0);
    }
}
