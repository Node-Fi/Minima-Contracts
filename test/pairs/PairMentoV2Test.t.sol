// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// solhint-disable no-console

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IMentoBroker} from "src/interfaces/mento/IMentoBroker.sol";

import {PairMentoV2} from "src/pairs/PairMentoV2.sol";

contract PairMentoV2Test is Test {
    string public baklavaRpcUrl = vm.envString("BAKLAVA_RPC_URL");

    // Baklava contract addresses
    address public constant CELO_ADDRESS =
        0xdDc9bE57f553fe75752D61606B94CBD7e0264eF8;
    address public constant CUSD_ADDRESS =
        0x62492A644A588FD904270BeD06ad52B9abfEA1aE;

    PairMentoV2 public pairMentoV2;

    function setUp() public {
        vm.createSelectFork(baklavaRpcUrl);

        pairMentoV2 = new PairMentoV2();
    }

    // Helper function to mint celo to an address
    function mintCelo(address to, uint256 amount) private {
        vm.startPrank(address(0));
        CELO_ADDRESS.call(
            abi.encodeWithSignature("mint(address,uint256)", to, amount)
        );
        vm.stopPrank();
    }

    function testSwapCeloToCusd() public {
        address trader = makeAddr("trader");

        // TODO: check mint
        mintCelo(trader, 1 ether);

        uint256 traderCeloBefore = IERC20(CELO_ADDRESS).balanceOf(trader);
        uint256 traderCusdBefore = IERC20(CUSD_ADDRESS).balanceOf(trader);

        assertTrue(traderCusdBefore == 0);

        IMentoBroker broker = pairMentoV2.getMentoBroker();

        (address exchangeProviderAddress, bytes32 exchangeId) = pairMentoV2
            .getExchangeInfoForTokens(CELO_ADDRESS, CUSD_ADDRESS, broker);

        assertTrue(exchangeProviderAddress != address(0));
        assertTrue(exchangeId != bytes32(0));

        // TODO: Need to get amount out...
        bytes swapData = abi.encode(exchangeProviderAddress, exchangeId, 0);

        changePrank(trader);
        IERC20(CELO_ADDRESS).transfer(address(traderCeloBefore), 1 ether);

        pairMentoV2.swap(CELO_ADDRESS, CUSD_ADDRESS, trader, swapData);

        uint256 traderCeloAfter = IERC20(CELO_ADDRESS).balanceOf(trader);
        uint256 traderCusdAfter = IERC20(CUSD_ADDRESS).balanceOf(trader);

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
