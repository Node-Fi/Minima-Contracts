// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// solhint-disable no-console

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IMentoBroker} from "src/interfaces/mento/IMentoBroker.sol";

import {PairMentoV2} from "src/pairs/PairMentoV2.sol";

interface IStableToken {
    function mint(address, uint256) external returns (bool);
}

contract PairMentoV2Test is Test {
    string public baklavaRpcUrl = vm.envString("BAKLAVA_RPC_URL");

    // Baklava contract addresses
    address public constant CELO_ADDRESS =
        0xdDc9bE57f553fe75752D61606B94CBD7e0264eF8;
    address public constant CUSD_ADDRESS =
        0x62492A644A588FD904270BeD06ad52B9abfEA1aE;
    address public constant MENTO_GRANDA =
        0xdfd641aB188Add84B317fB0b241F6b879E5EF906;

    PairMentoV2 public pairMentoV2;

    function setUp() public {
        vm.createSelectFork(baklavaRpcUrl);

        pairMentoV2 = new PairMentoV2();

        // Mint CUSD to pair
        changePrank(MENTO_GRANDA);
        IStableToken(CUSD_ADDRESS).mint(address(pairMentoV2), 1 ether);
    }

    function testSwapCeloToCusd() public {
        address trader = makeAddr("trader");

        // CUSD is going to pair but not coming out

        // Get expected out
        uint256 amountOutMin = pairMentoV2.getOutputAmount(
            CUSD_ADDRESS,
            CELO_ADDRESS,
            1 ether,
            ""
        );

        uint256 traderCeloBefore = IERC20(CELO_ADDRESS).balanceOf(trader);
        uint256 traderCusdBefore = IERC20(CUSD_ADDRESS).balanceOf(trader);

        // Verify trader has no CELO
        assertTrue(traderCeloBefore == 0);

        // Get the broker address
        IMentoBroker broker = pairMentoV2.getMentoBroker();

        // Get the exchange info
        (address exchangeProviderAddress, bytes32 exchangeId) = pairMentoV2
            .getExchangeInfoForTokens(CELO_ADDRESS, CUSD_ADDRESS, broker);

        // Verify we have a valid exchange for the tokens
        assertTrue(exchangeProviderAddress != address(0));
        assertTrue(exchangeId != bytes32(0));

        bytes memory swapData = abi.encode(
            exchangeProviderAddress,
            exchangeId,
            amountOutMin
        );

        uint256 pairBalanceBefore = IERC20(CUSD_ADDRESS).balanceOf(
            address(pairMentoV2)
        );

        uint256 pairBalanceAfter = IERC20(CUSD_ADDRESS).balanceOf(
            address(pairMentoV2)
        );

        // Swap CUSD for CELO with trader as recipient trader.
        pairMentoV2.swap(CUSD_ADDRESS, CELO_ADDRESS, trader, swapData);

        uint256 traderCeloAfter = IERC20(CELO_ADDRESS).balanceOf(trader);
        uint256 traderCusdAfter = IERC20(CUSD_ADDRESS).balanceOf(trader);

        console.log("traderCeloBefore: %s", traderCeloBefore);
        console.log("traderCeloAfter: %s", traderCeloAfter);

        console.log("traderCusdBefore: %s", traderCusdBefore);
        console.log("traderCusdAfter: %s", traderCusdAfter);

        assertTrue(traderCeloAfter == 0);
        assertTrue(traderCusdAfter > 0);
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
