pragma solidity 0.8.18;

import {MockErc20} from "../mock/MockErc20.sol";
import {MockFailingErc20} from "../mock/MockFailingErc20.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Test} from "forge-std/Test.sol";

import {MinimaRouterV1} from "../../src/MinimaRouterV1.sol";
import {IMinimaRouterV1} from "../../src/interfaces/IMinimaRouterV1.sol";
import {MockPair} from "../mock/MockPair.sol";
import {MockMultisig} from "../mock/MockMultisig.sol";
import {MinimaRouterV1External} from "../mock/MinimaRouterV1External.sol";

import "forge-std/console.sol";

import {ExtendedDSTest} from "../utils/ExtendedDSTest.sol";

/*
    Dependency: None
*/
contract MinimaRouterV1Test is ExtendedDSTest {
    event AdminFeeRecovered(address token, address reciever, uint256 amount);

    event AdminChanged(address addr, bool isAdmin);

    event PartnerAdminChanged(uint256 partnerId, address addr);

    uint256 constant NUM_TOKENS = 255;

    MinimaRouterV1 public minimaRouter;
    MockPair public pair;
    MockMultisig public multisig;
    MinimaRouterV1External public minimaRouterExternal;

    MockErc20[NUM_TOKENS] public tokens;

    function setUp() public override {
        ExtendedDSTest.setUp();

        multisig = new MockMultisig();

        address[] memory adminSigners = new address[](1);
        adminSigners[0] = alice;
        minimaRouter = new MinimaRouterV1(address(multisig), adminSigners);
        minimaRouterExternal = new MinimaRouterV1External(
            address(multisig),
            adminSigners
        );

        multisig.transferMinima(minimaRouter, alice); //current intended behavior is to allow for transfer to EOA later. I'm taking advtage of that for testing.
        multisig.transferMinima(minimaRouterExternal, alice);

        pair = new MockPair();

        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            MockErc20 token = new MockErc20("TEST TOKEN", Strings.toString(i));
            tokens[i] = token;
            vm.label(
                address(token),
                string(abi.encodePacked("Token ", Strings.toString(i)))
            );
            token.mint(alice, 2**127);
        }
    }

    modifier asUser(address _addr) {
        vm.startPrank(_addr);
        _;
        vm.stopPrank();
    }

    function testSwapTransferFailBetweenRoutes(uint8 tradeLen)
        public
        asUser(alice)
    {
        uint256 inputAmount = 1000000;
        MockFailingErc20 badToken = new MockFailingErc20("BAD", "BAD");
        tokens[0].mint(alice, inputAmount);

        if (tradeLen < 4 || inputAmount == 0) {
            return;
        }

        address[][] memory path = new address[][](2);
        address[][] memory pairs = new address[][](2);
        bytes[][] memory extras = new bytes[][](2);

        uint256[] memory inputAmounts = new uint256[](2); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](1);

        MockErc20 inputToken = tokens[0];

        path[0] = new address[](2);
        pairs[0] = new address[](1);
        extras[0] = new bytes[](1);
        inputAmounts[0] = inputAmount;
        path[0][0] = address(tokens[0]);
        path[0][1] = address(badToken);
        pairs[0][0] = address(pair);
        extras[0][0] = new bytes(0);
        divisors[0] = new IMinimaRouterV1.Divisor[](1);
        divisors[0][0] = IMinimaRouterV1.Divisor({
            toIdx: 1,
            divisor: 100,
            token: address(badToken)
        });

        path[1] = new address[](tradeLen - tradeLen / 2);
        pairs[1] = new address[]((tradeLen - tradeLen / 2) - 1);
        extras[1] = new bytes[]((tradeLen - tradeLen / 2) - 1);
        for (uint8 i = 0; i < tradeLen - tradeLen / 2; i++) {
            path[1][i] = address(tokens[i + tradeLen / 2]);

            if (i > 0) {
                pairs[1][i - 1] = address(pair);
                extras[1][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount,
                expectedOutputAmount: inputAmount,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);

        vm.expectRevert(bytes("MinimaRouterV1: Transfer to pair failed!"));
        minimaRouter.swapExactInputForOutput(payload);
    }

    function testDisperseWFeesTransferFail() public asUser(alice) {
        MockFailingErc20 badToken = new MockFailingErc20("BAD", "BAD");
        badToken.mint(address(minimaRouterExternal), 100000000000);
        vm.expectRevert(bytes("MinimaRouter: Final transfer failed!"));
        minimaRouterExternal.disperseWithFee__External(
            address(badToken),
            0,
            1,
            2,
            alice,
            0
        );
    }

    function testRecoverAdminFeeTransferFail() public asUser(alice) {
        MockFailingErc20 badToken = new MockFailingErc20("BAD", "BAD");
        vm.expectRevert(bytes("MinimaRouterV1: Admin fee transfer failed!"));
        minimaRouter.recoverAdminFee(address(badToken), alice);
    }

    function testPartnerAdminChanged() public asUser(alice) {
        vm.expectEmit(true, false, false, true);
        emit PartnerAdminChanged(10, address(3));
        minimaRouter.setPartnerAdmin(10, address(3));
    }

    function testAdminChangedEvent() public asUser(alice) {
        vm.expectEmit(true, false, false, true);
        emit AdminChanged(address(3), true);
        minimaRouter.setAdmin(address(3), true);
    }

    function testRecoverAdminFeeEvent() public asUser(alice) {
        vm.expectEmit(true, true, false, true);
        emit AdminFeeRecovered(address(tokens[0]), alice, 0);
        minimaRouter.recoverAdminFee(address(tokens[0]), alice);
    }

    function testAdminIsContract() public asUser(alice) {
        address[] memory adminSigners = new address[](1);
        adminSigners[0] = address(1);

        vm.expectRevert(
            "MinimaRouterV1: Minima must be deployed from contract!"
        );
        MinimaRouterV1 testRouter = new MinimaRouterV1(alice, adminSigners);

        testRouter = new MinimaRouterV1(address(multisig), adminSigners);
    }

    function testRenounceOwnership() public asUser(alice) {
        address owner = minimaRouter.owner();
        assertEq(owner, alice);

        vm.expectRevert("MinimaRouterV1: Ownership can't be renounced!");
        minimaRouter.renounceOwnership();
        owner = minimaRouter.owner();
        assertEq(owner, alice);
    }

    function testTransferOwnership() public asUser(alice) {
        address[] memory adminSigners = new address[](1);
        adminSigners[0] = address(1);
        MinimaRouterV1 testRouter = new MinimaRouterV1(
            address(multisig),
            adminSigners
        );
        multisig.transferMinima(testRouter, alice); //current intended behavior is to allow for transfer to EOA later. I'm taking advtage of that for testing.

        vm.expectRevert("Ownable: new owner is the zero address");
        testRouter.transferOwnership(address(0));

        testRouter.recoverAdminFee(address(tokens[0]), alice);
        address owner = testRouter.owner();
        assertEq(owner, alice);

        testRouter.transferOwnership(bob);
        owner = testRouter.owner();
        assertEq(owner, bob);

        vm.expectRevert("Unauthorized");
        testRouter.recoverAdminFee(address(tokens[0]), alice);
    }

    function testSetPartnerFeeSameAsOld() public asUser(alice) {
        minimaRouter.setPartnerFee(10, 5000);
        vm.expectRevert(
            bytes("MinimaRouterV1: Old fee can not equal new fee!")
        );
        minimaRouter.setPartnerFee(10, 5000);
    }

    function testRouteShouldFailWithMinOutGreaterThanExpectedOut(
        uint8 tradeLen,
        uint256 inputAmount
    ) public asUser(alice) {
        if (tradeLen < 4 || inputAmount == 0) {
            return;
        }

        address[][] memory path = new address[][](2);
        address[][] memory pairs = new address[][](2);
        bytes[][] memory extras = new bytes[][](2);

        uint256[] memory inputAmounts = new uint256[](2); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](1);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 outputBalanceBefore = outputToken.balanceOf(alice);
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }
        path[0] = new address[]((tradeLen / 2) + 1);
        pairs[0] = new address[](tradeLen / 2);
        extras[0] = new bytes[](tradeLen / 2);
        inputAmounts[0] = inputAmount;
        for (uint8 i = 0; i <= tradeLen / 2; i++) {
            path[0][i] = address(tokens[i]);

            if (i > 0) {
                pairs[0][i - 1] = address(pair);
                extras[0][i - 1] = new bytes(0);
            }
        }
        divisors[0] = new IMinimaRouterV1.Divisor[](1);
        divisors[0][0] = IMinimaRouterV1.Divisor({
            toIdx: 1,
            divisor: 100,
            token: address(tokens[tradeLen / 2])
        });

        path[1] = new address[](tradeLen - tradeLen / 2);
        pairs[1] = new address[]((tradeLen - tradeLen / 2) - 1);
        extras[1] = new bytes[]((tradeLen - tradeLen / 2) - 1);
        for (uint8 i = 0; i < tradeLen - tradeLen / 2; i++) {
            path[1][i] = address(tokens[i + tradeLen / 2]);

            if (i > 0) {
                pairs[1][i - 1] = address(pair);
                extras[1][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount + 1,
                expectedOutputAmount: inputAmount,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);
        vm.expectRevert(
            bytes(
                "MinimaRouterV1: expectedOutputAmount should be >= minOutputAmount"
            )
        );
        minimaRouter.swapExactInputForOutput(payload);
    }

    function testRouteShouldFailWithPairLenEq0(
        uint8 tradeLen,
        uint256 inputAmount
    ) public asUser(alice) {
        if (tradeLen < 4 || inputAmount == 0) {
            return;
        }

        address[][] memory path = new address[][](2);
        address[][] memory pairs = new address[][](2);
        bytes[][] memory extras = new bytes[][](2);

        uint256[] memory inputAmounts = new uint256[](2); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](1);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 outputBalanceBefore = outputToken.balanceOf(alice);
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }

        path[1] = new address[](tradeLen - tradeLen / 2);
        pairs[1] = new address[]((tradeLen - tradeLen / 2));
        extras[1] = new bytes[]((tradeLen - tradeLen / 2) - 1);
        for (uint8 i = 0; i < tradeLen - tradeLen / 2; i++) {
            path[1][i] = address(tokens[i + tradeLen / 2]);

            if (i > 0) {
                pairs[1][i - 1] = address(pair);
                extras[1][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount,
                expectedOutputAmount: inputAmount,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);
        vm.expectRevert(
            bytes("MinimaRouterV1: Inner pairs length can not be 0!")
        );
        minimaRouter.swapExactInputForOutput(payload);
    }

    function testShouldFailWithSetPartnerAdminAs0Address()
        public
        asUser(alice)
    {
        vm.expectRevert(bytes("MinimaRouterV1: Admin can not be 0 address!"));
        minimaRouter.setPartnerAdmin(0, address(0));
    }

    function testShouldFailWithSetAdminAs0Address() public asUser(alice) {
        vm.expectRevert(bytes("MinimaRouterV1: Admin can not be 0 address!"));
        minimaRouter.setAdmin(address(0), true);
    }

    function testShouldFailWithInitialSignersAs0Address() public {
        address[] memory adminSigners = new address[](1);
        adminSigners[0] = address(0);
        vm.expectRevert(
            bytes("MinimaRouterV1: Initial signers can not be 0 address!")
        );
        new MinimaRouterV1(address(multisig), adminSigners);
    }

    function testShouldFailWithAdminAs0Address() public {
        address[] memory adminSigners = new address[](1);
        adminSigners[0] = alice;
        vm.expectRevert(bytes("MinimaRouterV1: Admin can not be 0 address!"));
        new MinimaRouterV1(address(0), adminSigners);
    }

    function testShouldFailWithRecoverAdminFeeReceiver0Address()
        public
        asUser(alice)
    {
        vm.expectRevert(
            bytes("MinimaRouterV1: Reciever can not be 0 address!")
        );
        minimaRouter.recoverAdminFee(address(tokens[0]), address(0));
    }

    function testRouteShouldFailWithPathPairsMismatch(
        uint8 tradeLen,
        uint256 inputAmount
    ) public asUser(alice) {
        if (tradeLen < 4 || inputAmount == 0) {
            return;
        }

        address[][] memory path = new address[][](2);
        address[][] memory pairs = new address[][](2);
        bytes[][] memory extras = new bytes[][](2);

        uint256[] memory inputAmounts = new uint256[](2); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](1);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 outputBalanceBefore = outputToken.balanceOf(alice);
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }
        path[0] = new address[]((tradeLen / 2) + 1);
        pairs[0] = new address[](tradeLen / 2);
        extras[0] = new bytes[](tradeLen / 2);
        inputAmounts[0] = inputAmount;
        for (uint8 i = 0; i <= tradeLen / 2; i++) {
            path[0][i] = address(tokens[i]);

            if (i > 0) {
                pairs[0][i - 1] = address(pair);
                extras[0][i - 1] = new bytes(0);
            }
        }
        divisors[0] = new IMinimaRouterV1.Divisor[](1);
        divisors[0][0] = IMinimaRouterV1.Divisor({
            toIdx: 1,
            divisor: 100,
            token: address(tokens[tradeLen / 2])
        });

        path[1] = new address[](tradeLen - tradeLen / 2);
        pairs[1] = new address[]((tradeLen - tradeLen / 2));
        extras[1] = new bytes[]((tradeLen - tradeLen / 2) - 1);
        for (uint8 i = 0; i < tradeLen - tradeLen / 2; i++) {
            path[1][i] = address(tokens[i + tradeLen / 2]);

            if (i > 0) {
                pairs[1][i - 1] = address(pair);
                extras[1][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount,
                expectedOutputAmount: inputAmount,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);
        vm.expectRevert(
            bytes("MinimaRouterV1: Inner path and pairs length mismatch!")
        );
        minimaRouter.swapExactInputForOutput(payload);
    }

    function testShouldFailOnRandomEthSend() public asUser(alice) {
        vm.deal(alice, 1 ether);
        (bool sent, bytes memory data) = payable(address(minimaRouter)).call{
            value: 1 ether
        }("");
        assertEq(sent, false);
    }

    function testRouteShouldFailOnTransferToCurrentPath(
        uint8 tradeLen,
        uint256 inputAmount
    ) public asUser(alice) {
        if (tradeLen < 4 || inputAmount == 0) {
            return;
        }

        address[][] memory path = new address[][](2);
        address[][] memory pairs = new address[][](2);
        bytes[][] memory extras = new bytes[][](2);

        uint256[] memory inputAmounts = new uint256[](2); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](1);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 outputBalanceBefore = outputToken.balanceOf(alice);
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }
        path[0] = new address[]((tradeLen / 2) + 1);
        pairs[0] = new address[](tradeLen / 2);
        extras[0] = new bytes[](tradeLen / 2);
        inputAmounts[0] = inputAmount;
        for (uint8 i = 0; i <= tradeLen / 2; i++) {
            path[0][i] = address(tokens[i]);

            if (i > 0) {
                pairs[0][i - 1] = address(pair);
                extras[0][i - 1] = new bytes(0);
            }
        }
        divisors[0] = new IMinimaRouterV1.Divisor[](1);
        divisors[0][0] = IMinimaRouterV1.Divisor({
            toIdx: 0,
            divisor: 100,
            token: address(tokens[tradeLen / 2])
        });

        path[1] = new address[](tradeLen - tradeLen / 2);
        pairs[1] = new address[]((tradeLen - tradeLen / 2) - 1);
        extras[1] = new bytes[]((tradeLen - tradeLen / 2) - 1);
        for (uint8 i = 0; i < tradeLen - tradeLen / 2; i++) {
            path[1][i] = address(tokens[i + tradeLen / 2]);

            if (i > 0) {
                pairs[1][i - 1] = address(pair);
                extras[1][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount,
                expectedOutputAmount: inputAmount,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);
        vm.expectRevert(
            bytes("MinimaRouterV1: Can not transfer to completed path!")
        );
        minimaRouter.swapExactInputForOutput(payload);
    }

    function testRouteShouldFailOnTransferToCompletedPath(
        uint8 tradeLen,
        uint256 inputAmount
    ) public asUser(alice) {
        if (tradeLen < 4 || inputAmount == 0) {
            return;
        }

        address[][] memory path = new address[][](3);
        address[][] memory pairs = new address[][](3);
        bytes[][] memory extras = new bytes[][](3);

        uint256[] memory inputAmounts = new uint256[](3); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](2);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 outputBalanceBefore = outputToken.balanceOf(alice);
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }
        path[0] = new address[]((tradeLen / 2) + 1);
        pairs[0] = new address[](tradeLen / 2);
        extras[0] = new bytes[](tradeLen / 2);
        inputAmounts[0] = inputAmount;
        for (uint8 i = 0; i <= tradeLen / 2; i++) {
            path[0][i] = address(tokens[i]);

            if (i > 0) {
                pairs[0][i - 1] = address(pair);
                extras[0][i - 1] = new bytes(0);
            }
        }
        divisors[0] = new IMinimaRouterV1.Divisor[](1);
        divisors[0][0] = IMinimaRouterV1.Divisor({
            toIdx: 1,
            divisor: 100,
            token: address(tokens[tradeLen / 2])
        });

        path[1] = new address[](tradeLen - tradeLen / 2);
        pairs[1] = new address[]((tradeLen - tradeLen / 2) - 1);
        extras[1] = new bytes[]((tradeLen - tradeLen / 2) - 1);
        for (uint8 i = 0; i < tradeLen - tradeLen / 2; i++) {
            path[1][i] = address(tokens[i + tradeLen / 2]);

            if (i > 0) {
                pairs[1][i - 1] = address(pair);
                extras[1][i - 1] = new bytes(0);
            }
        }
        divisors[1] = new IMinimaRouterV1.Divisor[](1);
        divisors[1][0] = IMinimaRouterV1.Divisor({
            toIdx: 0,
            divisor: 100,
            token: address(tokens[tradeLen / 2])
        });

        path[2] = new address[](tradeLen - tradeLen / 2);
        pairs[2] = new address[]((tradeLen - tradeLen / 2) - 1);
        extras[2] = new bytes[]((tradeLen - tradeLen / 2) - 1);
        for (uint8 i = 0; i < tradeLen - tradeLen / 2; i++) {
            path[2][i] = address(tokens[i + tradeLen / 2]);

            if (i > 0) {
                pairs[2][i - 1] = address(pair);
                extras[2][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount,
                expectedOutputAmount: inputAmount,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);
        vm.expectRevert(
            bytes("MinimaRouterV1: Can not transfer to completed path!")
        );
        minimaRouter.swapExactInputForOutput(payload);
    }

    function testSetAdminFailsOnNonAuthorized(address prankster)
        public
        asUser(prankster)
    {
        if (prankster == alice) {
            return;
        }

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        minimaRouter.setAdmin(prankster, true);
    }

    function testShouldFailWhenDivisorIsZero(uint8 token) public {
        IMinimaRouterV1.Divisor[]
            memory divisors = new IMinimaRouterV1.Divisor[](1);
        divisors[0] = IMinimaRouterV1.Divisor({
            toIdx: 1,
            divisor: 0,
            token: address(tokens[token % NUM_TOKENS])
        });
        vm.expectRevert(bytes("MinimaRouter: Divisor too low"));
        minimaRouterExternal.getDivisorTransferAmounts__External(divisors);
    }

    function testShouldFailWhenDivisorIsTooHigh(uint8 token, uint8 _amount)
        public
    {
        IMinimaRouterV1.Divisor[]
            memory divisors = new IMinimaRouterV1.Divisor[](1);
        uint8 amount = (_amount % 100) + 101;
        divisors[0] = IMinimaRouterV1.Divisor({
            toIdx: 1,
            divisor: amount,
            token: address(tokens[token % NUM_TOKENS])
        });
        vm.expectRevert(bytes("MinimaRouter: Divisor too high"));
        minimaRouterExternal.getDivisorTransferAmounts__External(divisors);
    }

    function testShouldFailWhenDivisorsDoNotSumTo100() public {
        IMinimaRouterV1.Divisor[]
            memory divisors = new IMinimaRouterV1.Divisor[](2);
        divisors[0] = IMinimaRouterV1.Divisor({
            toIdx: 1,
            divisor: 50,
            token: address(tokens[0])
        });
        divisors[1] = IMinimaRouterV1.Divisor({
            toIdx: 1,
            divisor: 49,
            token: address(tokens[0])
        });
        vm.expectRevert(bytes("MinimaRouter: Invalid divisors"));
        minimaRouterExternal.getDivisorTransferAmounts__External(divisors);
    }

    function testShouldFailWhenDivisorsDoNotSumTo100Fuzz(uint8 numDivisors)
        public
    {
        if (numDivisors == 0) {
            return;
        }

        IMinimaRouterV1.Divisor[]
            memory divisors = new IMinimaRouterV1.Divisor[](numDivisors);
        for (uint8 i = 0; i < numDivisors; i++) {
            divisors[i] = IMinimaRouterV1.Divisor({
                toIdx: 1,
                divisor: 99,
                token: address(tokens[i % NUM_TOKENS])
            });
        }
        vm.expectRevert(bytes("MinimaRouter: Invalid divisors"));
        minimaRouterExternal.getDivisorTransferAmounts__External(divisors);
    }

    function testgetPartnerIdFromSigReturns0OnInvalidEcRecover() public {
        uint256 partnerId = 9;
        uint256 deadline = block.timestamp + 1000;
        address tokenIn = address(tokens[0]);
        address tokenOut = address(tokens[1]);
        bytes memory sig = new bytes(65);
        bytes32 message = minimaRouterExternal.prefixed__External(
            keccak256(
                abi.encodePacked(
                    partnerId,
                    deadline,
                    tokenIn,
                    tokenOut,
                    minimaRouterExternal
                )
            )
        );

        sig[64] = 0x01;

        (uint8 v, bytes32 r, bytes32 s) = minimaRouterExternal
            .splitSignature__External(sig);

        // ecrecover should fail if v is not 27 or 28
        assertEq(uint256(v), 1);

        address expectedSigner = ecrecover(message, v, r, s);

        assertEq(expectedSigner, address(0));

        vm.expectRevert("ECDSA: invalid signature");
        uint256 partnerInfo = minimaRouterExternal
            .getPartnerIdFromSig__External(
                partnerId,
                deadline,
                tokenIn,
                tokenOut,
                sig
            );
    }

    function testSetPartnerFee(uint256 feeNumerator, uint256 partnerId)
        public
        asUser(alice)
    {
        uint256 oldFee = minimaRouter.getPartnerFee(partnerId);

        if (feeNumerator > minimaRouter.MAX_PARTNER_FEE()) {
            vm.expectRevert(bytes("MinimaRouterV1: Fee too high"));
            minimaRouter.setPartnerFee(partnerId, feeNumerator);
        } else if (oldFee == feeNumerator) {
            vm.expectRevert(
                bytes("MinimaRouterV1: Old fee can not equal new fee!")
            );
            minimaRouter.setPartnerFee(partnerId, feeNumerator);
        } else {
            minimaRouter.setPartnerFee(partnerId, feeNumerator);
            uint256 newFee = minimaRouter.getPartnerFee(partnerId);
            assertEq(newFee, feeNumerator);
        }
    }

    function testRouteSuccessful(uint8 tradeLen, uint256 inputAmount)
        public
        asUser(alice)
    {
        if (tradeLen < 2) {
            return;
        }

        address[][] memory path = new address[][](1);
        address[][] memory pairs = new address[][](1);
        bytes[][] memory extras = new bytes[][](1);

        uint256[] memory inputAmounts = new uint256[](1); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](0);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 outputBalanceBefore = outputToken.balanceOf(alice);
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }
        path[0] = new address[](tradeLen);
        pairs[0] = new address[](tradeLen - 1);
        extras[0] = new bytes[](tradeLen - 1);
        inputAmounts[0] = inputAmount;
        for (uint8 i = 0; i < tradeLen; i++) {
            path[0][i] = address(tokens[i]);

            if (i > 0) {
                pairs[0][i - 1] = address(pair);
                extras[0][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount,
                expectedOutputAmount: inputAmount,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);
        minimaRouter.swapExactInputForOutput(payload);

        uint256 outputBalanceAfter = outputToken.balanceOf(alice);
        uint256 inputBalanceAfter = inputToken.balanceOf(alice);

        assertEq(
            outputBalanceAfter,
            outputBalanceBefore + inputAmount,
            "Insufficent output"
        );
        assertEq(
            inputBalanceAfter,
            inputBalanceBefore - inputAmount,
            "Not enough input taken"
        );
    }

    function testRouteSuccessfulSplit(uint8 tradeLen, uint256 inputAmount)
        public
        asUser(alice)
    {
        if (tradeLen < 4 || inputAmount == 0) {
            return;
        }

        address[][] memory path = new address[][](2);
        address[][] memory pairs = new address[][](2);
        bytes[][] memory extras = new bytes[][](2);

        uint256[] memory inputAmounts = new uint256[](2); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](1);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 outputBalanceBefore = outputToken.balanceOf(alice);
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }
        path[0] = new address[]((tradeLen / 2) + 1);
        pairs[0] = new address[](tradeLen / 2);
        extras[0] = new bytes[](tradeLen / 2);
        inputAmounts[0] = inputAmount;
        for (uint8 i = 0; i <= tradeLen / 2; i++) {
            path[0][i] = address(tokens[i]);

            if (i > 0) {
                pairs[0][i - 1] = address(pair);
                extras[0][i - 1] = new bytes(0);
            }
        }
        divisors[0] = new IMinimaRouterV1.Divisor[](1);
        divisors[0][0] = IMinimaRouterV1.Divisor({
            toIdx: 1,
            divisor: 100,
            token: address(tokens[tradeLen / 2])
        });

        path[1] = new address[](tradeLen - tradeLen / 2);
        pairs[1] = new address[]((tradeLen - tradeLen / 2) - 1);
        extras[1] = new bytes[]((tradeLen - tradeLen / 2) - 1);
        for (uint8 i = 0; i < tradeLen - tradeLen / 2; i++) {
            path[1][i] = address(tokens[i + tradeLen / 2]);

            if (i > 0) {
                pairs[1][i - 1] = address(pair);
                extras[1][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount,
                expectedOutputAmount: inputAmount,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);
        minimaRouter.swapExactInputForOutput(payload);

        uint256 outputBalanceAfter = outputToken.balanceOf(alice);
        uint256 inputBalanceAfter = inputToken.balanceOf(alice);

        assertEq(
            outputBalanceAfter,
            outputBalanceBefore + inputAmount,
            "Insufficent output"
        );
        assertEq(
            inputBalanceAfter,
            inputBalanceBefore - inputAmount,
            "Not enough input taken"
        );
    }

    function testAllowsOutputTokenToIdx0(uint8 tradeLen, uint256 inputAmount)
        public
        asUser(alice)
    {
        if (
            tradeLen > 128 ||
            tradeLen < 4 ||
            inputAmount == 0 ||
            inputAmount >= 2**255
        ) {
            return;
        }

        address[][] memory path = new address[][](2);
        address[][] memory pairs = new address[][](2);
        bytes[][] memory extras = new bytes[][](2);

        uint256[] memory inputAmounts = new uint256[](2); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](1);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 outputBalanceBefore = outputToken.balanceOf(alice);
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }
        path[0] = new address[](tradeLen);
        pairs[0] = new address[](tradeLen - 1);
        extras[0] = new bytes[](tradeLen - 1);
        inputAmounts[0] = inputAmount;
        for (uint8 i = 0; i < tradeLen; i++) {
            path[0][i] = address(tokens[i]);

            if (i > 0) {
                pairs[0][i - 1] = address(pair);
                extras[0][i - 1] = new bytes(0);
            }
        }
        divisors[0] = new IMinimaRouterV1.Divisor[](1);

        // toIdx of 0 with the output token should be allowed
        divisors[0][0] = IMinimaRouterV1.Divisor({
            toIdx: 0,
            divisor: 100,
            token: address(outputToken)
        });

        inputAmounts[1] = inputAmount;
        path[1] = new address[](tradeLen);
        pairs[1] = new address[](tradeLen - 1);
        extras[1] = new bytes[](tradeLen - 1);
        for (uint8 i = 0; i < tradeLen; i++) {
            path[1][i] = address(tokens[i]);

            if (i > 0) {
                pairs[1][i - 1] = address(pair);
                extras[1][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount,
                expectedOutputAmount: inputAmount * 2,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount * 2);
        minimaRouter.swapExactInputForOutput(payload);

        uint256 outputBalanceAfter = outputToken.balanceOf(alice);
        uint256 inputBalanceAfter = inputToken.balanceOf(alice);

        assertEq(
            outputBalanceAfter,
            outputBalanceBefore + (inputAmount * 2),
            "Insufficent output"
        );
        assertEq(
            inputBalanceAfter,
            inputBalanceBefore - (inputAmount * 2),
            "Not enough input taken"
        );
    }

    function testRouteFailsWhenDivisorTooHigh(
        uint8 tradeLen,
        uint256 inputAmount
    ) public asUser(alice) {
        if (tradeLen < 4 || inputAmount == 0) {
            return;
        }

        address[][] memory path = new address[][](2);
        address[][] memory pairs = new address[][](2);
        bytes[][] memory extras = new bytes[][](2);

        uint256[] memory inputAmounts = new uint256[](2); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](1);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }
        path[0] = new address[]((tradeLen / 2) + 1);
        pairs[0] = new address[](tradeLen / 2);
        extras[0] = new bytes[](tradeLen / 2);
        inputAmounts[0] = inputAmount;
        for (uint8 i = 0; i <= tradeLen / 2; i++) {
            path[0][i] = address(tokens[i]);

            if (i > 0) {
                pairs[0][i - 1] = address(pair);
                extras[0][i - 1] = new bytes(0);
            }
        }
        divisors[0] = new IMinimaRouterV1.Divisor[](1);
        divisors[0][0] = IMinimaRouterV1.Divisor({
            toIdx: 1,
            divisor: 101,
            token: address(tokens[tradeLen / 2])
        });

        path[1] = new address[](tradeLen - tradeLen / 2);
        pairs[1] = new address[]((tradeLen - tradeLen / 2) - 1);
        extras[1] = new bytes[]((tradeLen - tradeLen / 2) - 1);
        for (uint8 i = 0; i < tradeLen - tradeLen / 2; i++) {
            path[1][i] = address(tokens[i + tradeLen / 2]);

            if (i > 0) {
                pairs[1][i - 1] = address(pair);
                extras[1][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount,
                expectedOutputAmount: inputAmount,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);
        vm.expectRevert(bytes("MinimaRouter: Divisor too high"));
        minimaRouter.swapExactInputForOutput(payload);
    }

    function testRouteHandlesDivisor(
        uint8 tradeLen,
        uint256 inputAmount,
        uint8 divisor
    ) public asUser(alice) {
        divisor = divisor % 100;
        if (tradeLen < 4 || inputAmount < 100 || divisor == 0) {
            return;
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: new address[][](2),
                pairs: new address[][](2),
                extras: new bytes[][](2),
                divisors: new IMinimaRouterV1.Divisor[][](1),
                inputAmounts: new uint256[](2),
                minOutputAmount: 0,
                expectedOutputAmount: inputAmount,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });
        MockErc20 outputToken;
        MockErc20 inputToken;
        uint256 outputBalanceBefore;
        uint256 inputBalanceBefore;

        {
            outputToken = tokens[tradeLen - 1];
            inputToken = tokens[0];
            outputBalanceBefore = outputToken.balanceOf(alice);
            inputBalanceBefore = inputToken.balanceOf(alice);

            if (inputBalanceBefore < inputAmount) {
                return;
            }
            payload.path[0] = new address[]((tradeLen / 2) + 1);
            payload.pairs[0] = new address[](tradeLen / 2);
            payload.extras[0] = new bytes[](tradeLen / 2);

            for (uint8 i = 0; i <= tradeLen / 2; i++) {
                payload.path[0][i] = address(tokens[i]);

                if (i > 0) {
                    payload.pairs[0][i - 1] = address(pair);
                    payload.extras[0][i - 1] = new bytes(0);
                }
            }
            payload.divisors[0] = new IMinimaRouterV1.Divisor[](2);
            payload.divisors[0][0] = IMinimaRouterV1.Divisor({
                toIdx: 1,
                divisor: divisor,
                token: address(tokens[tradeLen / 2])
            });
            payload.divisors[0][1] = IMinimaRouterV1.Divisor({
                toIdx: 1,
                divisor: 100 - divisor,
                token: address(tokens[tradeLen / 2])
            });

            payload.path[1] = new address[](tradeLen - tradeLen / 2);
            payload.pairs[1] = new address[]((tradeLen - tradeLen / 2) - 1);
            payload.extras[1] = new bytes[]((tradeLen - tradeLen / 2) - 1);
            for (uint8 i = 0; i < tradeLen - tradeLen / 2; i++) {
                payload.path[1][i] = address(tokens[i + tradeLen / 2]);

                if (i > 0) {
                    payload.pairs[1][i - 1] = address(pair);
                    payload.extras[1][i - 1] = new bytes(0);
                }
            }
        }

        payload.inputAmounts[0] = inputAmount;
        inputToken.approve(address(minimaRouter), inputAmount);
        minimaRouter.swapExactInputForOutput(payload);

        uint256 outputBalanceAfter = outputToken.balanceOf(alice);
        uint256 inputBalanceAfter = inputToken.balanceOf(alice);

        assertApproxEq(
            outputBalanceAfter,
            outputBalanceBefore + inputAmount,
            1,
            "Insufficent output"
        );
        assertEq(
            inputBalanceAfter,
            inputBalanceBefore - inputAmount,
            "Not enough input taken"
        );
    }

    function testGivesExpectedAmountAsMax(uint8 tradeLen, uint256 inputAmount)
        public
        asUser(alice)
    {
        if (tradeLen < 2 || inputAmount < 10) {
            return;
        }

        IMinimaRouterV1.MultiSwapPayload memory payload;
        MockErc20 outputToken;
        MockErc20 inputToken;
        uint256 outputBalanceBefore;
        uint256 inputBalanceBefore;
        {
            address[][] memory path = new address[][](1);
            address[][] memory pairs = new address[][](1);
            bytes[][] memory extras = new bytes[][](1);

            uint256[] memory inputAmounts = new uint256[](1); //new uint256[](1);

            IMinimaRouterV1.Divisor[][]
                memory divisors = new IMinimaRouterV1.Divisor[][](0);

            outputToken = tokens[tradeLen - 1];
            inputToken = tokens[0];
            outputBalanceBefore = outputToken.balanceOf(alice);
            inputBalanceBefore = inputToken.balanceOf(alice);

            if (inputBalanceBefore < inputAmount) {
                return;
            }
            path[0] = new address[](tradeLen);
            pairs[0] = new address[](tradeLen - 1);
            extras[0] = new bytes[](tradeLen - 1);
            inputAmounts[0] = inputAmount;
            for (uint8 i = 0; i < tradeLen; i++) {
                path[0][i] = address(tokens[i]);

                if (i > 0) {
                    pairs[0][i - 1] = address(pair);
                    extras[0][i - 1] = new bytes(0);
                }
            }

            payload = IMinimaRouterV1.MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: 2,
                expectedOutputAmount: 10,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });
        }
        inputToken.approve(address(minimaRouter), inputAmount);
        minimaRouter.swapExactInputForOutput(payload);

        uint256 outputBalanceAfter = outputToken.balanceOf(alice);
        uint256 inputBalanceAfter = inputToken.balanceOf(alice);

        assertEq(
            outputBalanceAfter,
            outputBalanceBefore + 10,
            "Insufficent output"
        );
        assertEq(
            inputBalanceAfter,
            inputBalanceBefore - inputAmount,
            "Not enough input taken"
        );
    }

    function testPassesInbetweenExpectedAndMinimum(
        uint8 tradeLen,
        uint256 inputAmount
    ) public asUser(alice) {
        if (tradeLen < 2 || inputAmount == 0) {
            return;
        }

        address[][] memory path = new address[][](1);
        address[][] memory pairs = new address[][](1);
        bytes[][] memory extras = new bytes[][](1);

        uint256[] memory inputAmounts = new uint256[](1); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](0);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 outputBalanceBefore = outputToken.balanceOf(alice);
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }
        path[0] = new address[](tradeLen);
        pairs[0] = new address[](tradeLen - 1);
        extras[0] = new bytes[](tradeLen - 1);
        inputAmounts[0] = inputAmount;
        for (uint8 i = 0; i < tradeLen; i++) {
            path[0][i] = address(tokens[i]);

            if (i > 0) {
                pairs[0][i - 1] = address(pair);
                extras[0][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount - 1,
                expectedOutputAmount: inputAmount + 1,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);
        minimaRouter.swapExactInputForOutput(payload);

        uint256 outputBalanceAfter = outputToken.balanceOf(alice);
        uint256 inputBalanceAfter = inputToken.balanceOf(alice);

        assertEq(
            outputBalanceAfter,
            outputBalanceBefore + inputAmount,
            "Insufficent output"
        );
        assertEq(
            inputBalanceAfter,
            inputBalanceBefore - inputAmount,
            "Not enough input taken"
        );
    }

    function testRevertOnNotEnoughTokens(uint8 tradeLen, uint256 inputAmount)
        public
        asUser(alice)
    {
        if (tradeLen < 2 || inputAmount == 0) {
            return;
        }

        address[][] memory path = new address[][](1);
        address[][] memory pairs = new address[][](1);
        bytes[][] memory extras = new bytes[][](1);

        uint256[] memory inputAmounts = new uint256[](1); //new uint256[](1);

        IMinimaRouterV1.Divisor[][]
            memory divisors = new IMinimaRouterV1.Divisor[][](0);

        MockErc20 outputToken = tokens[tradeLen - 1];
        MockErc20 inputToken = tokens[0];
        uint256 outputBalanceBefore = outputToken.balanceOf(alice);
        uint256 inputBalanceBefore = inputToken.balanceOf(alice);

        if (inputBalanceBefore < inputAmount) {
            return;
        }
        path[0] = new address[](tradeLen);
        pairs[0] = new address[](tradeLen - 1);
        extras[0] = new bytes[](tradeLen - 1);
        inputAmounts[0] = inputAmount;
        for (uint8 i = 0; i < tradeLen; i++) {
            path[0][i] = address(tokens[i]);

            if (i > 0) {
                pairs[0][i - 1] = address(pair);
                extras[0][i - 1] = new bytes(0);
            }
        }

        IMinimaRouterV1.MultiSwapPayload memory payload = IMinimaRouterV1
            .MultiSwapPayload({
                path: path,
                pairs: pairs,
                extras: extras,
                divisors: divisors,
                inputAmounts: inputAmounts,
                minOutputAmount: inputAmount + 1,
                expectedOutputAmount: inputAmount + 1,
                to: alice,
                deadline: block.timestamp + 10,
                partner: 0,
                sig: new bytes(0)
            });

        inputToken.approve(address(minimaRouter), inputAmount);

        vm.expectRevert(bytes("MinimaRouter: Insufficient output"));
        minimaRouter.swapExactInputForOutput(payload);
    }
}
