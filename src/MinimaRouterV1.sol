// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/ISwappaPairV1.sol";
import "./interfaces/IMinimaRouterV1.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract MinimaRouterV1 is IMinimaRouterV1, Ownable {
    using SafeMath for uint256;

    // Tracks signers for approving routes
    mapping(address => bool) private adminSigner;

    // Tracks fees for partners.  Fee is calculated as fee / FEE_DENOMINATOR
    mapping(uint256 => uint256) private partnerFeesNumerator;

    // Tracks wallets that can control fee for a given partner
    mapping(uint256 => address) private partnerAdmin;

    // Tracks internal balances
    mapping(address => uint256) private outputBalancesBefore; //token => amount

    // Maximum fee that a partner can set is 5%
    // Minima takes no additional fee - fee is only taken by partners who integrate
    uint256 public constant MAX_PARTNER_FEE = 5 * 10**8;
    uint256 public constant FEE_DENOMINATOR = 10**10;

    uint256 public constant DIVISOR_DENOMINATOR = 100;

    event Swap(
        address indexed sender,
        address to,
        address indexed input,
        address output,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 indexed tenantId
    );

    event FeeChanged(
        uint256 indexed partnerId,
        address indexed initiator,
        bool indexed isAdminFee,
        uint256 oldFee,
        uint256 newFee
    );

    event AdminFeeRecovered(address token, address reciever, uint256 amount);

    event AdminChanged(address addr, bool isAdmin);

    event PartnerAdminChanged(uint256 partnerId, address addr);

    modifier partnerAuthorized(uint256 partnerId) {
        require(
            adminSigner[msg.sender] || partnerAdmin[partnerId] == msg.sender,
            "Unauthorized"
        );
        _;
    }

    modifier onlyAdmin() {
        require(
            adminSigner[msg.sender] || msg.sender == owner(),
            "Unauthorized"
        );
        _;
    }

    /**
     * [IMPORTANT]
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
		admin should be a multisig wallet
	 */
    constructor(address admin, address[] memory initialSigners)
        public
        Ownable()
    {
        require(
            admin != address(0),
            "MinimaRouterV1: Admin can not be 0 address!"
        );
        require(
            isContract(admin),
            "MinimaRouterV1: Minima must be deployed from contract!"
        );
        transferOwnership(admin);

        // Make the null tenant the admin wallet, with default fee numerator of 0
        partnerAdmin[0] = admin;

        // Add the initial signers
        for (uint8 i = 0; i < initialSigners.length; i++) {
            require(
                initialSigners[i] != address(0),
                "MinimaRouterV1: Initial signers can not be 0 address!"
            );
            adminSigner[initialSigners[i]] = true;
        }
    }

    function renounceOwnership() public override onlyOwner {
        revert("MinimaRouterV1: Ownership can't be renounced!");
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        partnerAdmin[0] = newOwner;
        super.transferOwnership(newOwner);
    }

    function recoverAdminFee(address token, address reciever)
        external
        onlyAdmin
    {
        require(
            reciever != address(0),
            "MinimaRouterV1: Reciever can not be 0 address!"
        );
        outputBalancesBefore[token] = 0;

        uint256 toClaim = IERC20(token).balanceOf(address(this));
        require(
            IERC20(token).transfer(reciever, toClaim),
            "MinimaRouterV1: Admin fee transfer failed!"
        );
        emit AdminFeeRecovered(token, reciever, toClaim);
    }

    function splitSignature(bytes memory sig)
        internal
        pure
        returns (
            uint8,
            bytes32,
            bytes32
        )
    {
        require(sig.length == 65, "signature is not 65 bytes");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    function setAdmin(address addr, bool isAdmin) external onlyOwner {
        require(
            addr != address(0),
            "MinimaRouterV1: Admin can not be 0 address!"
        );
        adminSigner[addr] = isAdmin;
        emit AdminChanged(addr, isAdmin);
    }

    function setPartnerAdmin(uint256 partnerId, address admin)
        external
        partnerAuthorized(partnerId)
    {
        require(
            admin != address(0),
            "MinimaRouterV1: Admin can not be 0 address!"
        );
        partnerAdmin[partnerId] = admin;
        emit PartnerAdminChanged(partnerId, admin);
    }

    function setPartnerFee(uint256 partnerId, uint256 feeNumerator)
        external
        partnerAuthorized(partnerId)
    {
        require(
            feeNumerator <= MAX_PARTNER_FEE,
            "MinimaRouterV1: Fee too high"
        );
        uint256 oldFee = partnerFeesNumerator[partnerId];
        require(
            oldFee != feeNumerator,
            "MinimaRouterV1: Old fee can not equal new fee!"
        );
        partnerFeesNumerator[partnerId] = feeNumerator;
        emit FeeChanged(partnerId, msg.sender, false, oldFee, feeNumerator);
    }

    // Builds a prefixed hash to mimic the behavior of eth_sign.
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }

    function recoverSigner(bytes32 message, bytes memory sig)
        internal
        pure
        returns (address)
    {
        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = splitSignature(sig);

        return ECDSA.recover(message, v, r, s);
    }

    function getPartnerFee(uint256 partnerId) external view returns (uint256) {
        return partnerFeesNumerator[partnerId];
    }

    function getPartnerIdFromSig(
        uint256 partnerId,
        uint256 deadline,
        address tokenIn,
        address tokenOut,
        bytes memory sig
    ) internal view returns (uint256 partner) {
        if (sig.length != 65) return 0; // Allow for unauthorized swaps, default to null tenant

        bytes32 message = prefixed(
            keccak256(abi.encodePacked(partnerId, deadline, tokenIn, tokenOut))
        );

        address signer = recoverSigner(message, sig);

        // QSP-1: Check for null return from ecrecover and for admin rights of signer
        if (signer != address(0) && adminSigner[signer]) {
            return partnerId;
        }
        return 0;
    }

    function getOutputAmount(
        address[] calldata path,
        address[] calldata pairs,
        bytes[] calldata extras,
        uint256 inputAmount
    ) external view override returns (uint256 outputAmount) {
        outputAmount = inputAmount;
        for (uint256 i = 0; i < pairs.length; i++) {
            outputAmount = ISwappaPairV1(pairs[i]).getOutputAmount(
                path[i],
                path[i + 1],
                outputAmount,
                extras[i]
            );
        }
    }

    // Disperse the output amount to the recipient, taking into account the partner fee and positive slippage.
    function disperseWithFee(
        address outputToken,
        uint256 minOutputAmount,
        uint256 expectedOutput,
        uint256 outputAmount,
        address to,
        uint256 partnerId
    ) internal returns (uint256) {
        uint256 partnerFee = outputAmount
            .mul(partnerFeesNumerator[partnerId])
            .div(FEE_DENOMINATOR);
        outputAmount = outputAmount.sub(partnerFee);
        outputAmount = outputAmount < expectedOutput
            ? outputAmount
            : expectedOutput; // Capture positive slippage

        require(
            outputAmount >= minOutputAmount,
            "MinimaRouter: Insufficient output"
        );

        require(
            IERC20(outputToken).transfer(to, outputAmount),
            "MinimaRouter: Final transfer failed!"
        );

        if (
            partnerFee > 0 &&
            !IERC20(outputToken).transfer(partnerAdmin[partnerId], partnerFee)
        ) {
            revert("MinimaRouter: Partner fee transfer failed");
        }

        // Record internal balance
        updateBalances(outputToken);
        return outputAmount;
    }

    function updateBalances(address output) internal returns (uint256) {
        outputBalancesBefore[output] = IERC20(output).balanceOf(address(this)); //Record the new fee balance
    }

    // Here we assume divisors are sorted by token address
    // For each token, a total weigh of 100 MUST be provided
    // Otherwise, the function will revert
    function getDivisorTransferAmounts(Divisor[] memory divisors)
        internal
        view
        returns (uint256[] memory)
    {
        // Weight sum is initially the expected total weight, and we decrement it by the weight of each token to track for correct weight instead of creating another variable
        uint256 weightSumExpected = 100;
        for (uint8 i = 1; i < divisors.length; i++) {
            // If i is not the same token as i-1, it must be a new token, so add 100 to the expected weight sum
            if (divisors[i].token != divisors[i - 1].token) {
                weightSumExpected = weightSumExpected.add(100);
            }
        }

        uint256[] memory transferAmounts = new uint256[](divisors.length);
        for (uint256 k = 0; k < divisors.length; k++) {
            uint8 weight = divisors[k].divisor;
            require(weight <= 100, "MinimaRouter: Divisor too high");
            require(weight > 0, "MinimaRouter: Divisor too low");
            require(
                weightSumExpected >= weight,
                "MinimaRouter: Invalid divisors"
            );

            weightSumExpected = weightSumExpected.sub(weight);

            uint256 swapResult = SafeMath.sub(
                IERC20(divisors[k].token).balanceOf(address(this)),
                outputBalancesBefore[divisors[k].token]
            );

            uint256 transferAmount = swapResult.mul(weight).div(
                DIVISOR_DENOMINATOR
            );
            transferAmounts[k] = transferAmount;
        }

        // If the weight sum is not 0, then the divisors are invalid
        require(weightSumExpected == 0, "MinimaRouter: Invalid divisors");
        return transferAmounts;
    }

    function swapExactInputForOutput(MultiSwapPayload calldata details)
        external
        override
        returns (uint256[] memory)
    {
        require(
            details.deadline >= block.timestamp,
            "MinimaRouterV1: Expired!"
        );
        require(
            details.path.length == details.pairs.length,
            "MinimaRouterV1: Path and Pairs mismatch!"
        );
        require(
            details.pairs.length == details.extras.length,
            "MinimaRouterV1: Pairs and Extras mismatch!"
        );
        require(
            details.pairs.length > 0,
            "MinimaRouterV1: Must have at least one pair!"
        );
        require(
            details.divisors.length == details.path.length - 1,
            "MinimaRouterV1: Each Path must have a divisor!"
        );
        require(
            details.inputAmounts.length == details.path.length,
            "MinimaRouterV1: Each Path must have an input amount!"
        );
        require(
            details.expectedOutputAmount >= details.minOutputAmount,
            "MinimaRouterV1: expectedOutputAmount should be >= minOutputAmount"
        );

        address output = details.path[details.path.length - 1][
            details.path[details.path.length - 1].length - 1
        ];

        for (uint256 i = 0; i < details.path.length; i++) {
            require(
                details.pairs[i].length > 0,
                "MinimaRouterV1: Inner pairs length can not be 0!"
            );
            require(
                details.pairs[i].length == details.path[i].length - 1,
                "MinimaRouterV1: Inner path and pairs length mismatch!"
            );
            //Transfer initial amounts
            if (details.inputAmounts[i] > 0) {
                require(
                    IERC20(details.path[i][0]).transferFrom(
                        msg.sender,
                        details.pairs[i][0],
                        details.inputAmounts[i]
                    ),
                    "MinimaRouterV1: Initial transferFrom failed!"
                );
            }

            for (uint256 j = 0; j < details.pairs[i].length; j++) {
                (address pairInput, address pairOutput) = (
                    details.path[i][j],
                    details.path[i][j + 1]
                );
                address next = j < details.pairs[i].length - 1
                    ? details.pairs[i][j + 1]
                    : address(this);

                ISwappaPairV1(details.pairs[i][j]).swap(
                    pairInput,
                    pairOutput,
                    next,
                    details.extras[i][j]
                );
            }

            if (i < details.path.length - 1) {
                uint256[] memory transferAmounts = getDivisorTransferAmounts(
                    details.divisors[i]
                );

                for (uint256 k = 0; k < transferAmounts.length; k++) {
                    uint8 toIdx = details.divisors[i][k].toIdx;

                    // Allow output token to stay in this contract, it will be transfered out following the complete path execution
                    if (toIdx == 0 && details.divisors[i][k].token == output) {
                        continue;
                    }

                    require(
                        toIdx > i,
                        "MinimaRouterV1: Can not transfer to completed path!"
                    );

                    if (transferAmounts[k] > 0) {
                        require(
                            IERC20(details.divisors[i][k].token).transfer(
                                details.pairs[toIdx][0],
                                transferAmounts[k]
                            ),
                            "MinimaRouterV1: Transfer to pair failed!"
                        );
                    }
                }
            }
        }

        uint256 tradeOutput = SafeMath.sub(
            IERC20(output).balanceOf(address(this)),
            outputBalancesBefore[output]
        );
        uint256 partnerId = getPartnerIdFromSig(
            details.partner,
            details.deadline,
            details.path[0][0],
            output,
            details.sig
        );
        uint256 outputAmount = disperseWithFee(
            output,
            details.minOutputAmount,
            details.expectedOutputAmount,
            tradeOutput,
            details.to,
            partnerId
        );
        emit Swap(
            msg.sender,
            details.to,
            details.path[0][0],
            output,
            details.inputAmounts[0],
            outputAmount,
            partnerId
        );
    }
}
