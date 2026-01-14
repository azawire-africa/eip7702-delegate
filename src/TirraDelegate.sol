// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITirraDelegate} from "./interfaces/ITirraDelegate.sol";
import {IntentHash} from "./libraries/IntentHash.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {
    Ownable2Step,
    Ownable
} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TirraDelegate
 * @author Tirra Protocol
 * @notice EIP-7702 Delegate Contract for gas-sponsored EOA transactions
 * @dev This contract acts as a strict execution layer for EOAs that delegate via EIP-7702
 *
 * Security Invariants:
 * 1. Only the delegating EOA can authorize execution (via signature)
 * 2. All calls must be to allowlisted targets + selectors
 * 3. Nonces are strictly sequential (no gaps, no reuse)
 * 4. Deadlines are enforced on-chain
 * 5. Fees are capped at MAX_FEE_BPS of user balance
 * 6. System fails closed on any validation failure
 */
contract TirraDelegate is
    ITirraDelegate,
    EIP712,
    Ownable2Step,
    ReentrancyGuard
{
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using IntentHash for Call[];
    using IntentHash for Intent;
    using IntentHash for Fee;
    using IntentHash for Constraints;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Maximum number of calls per batch
    uint256 public constant MAX_CALLS = 10;

    /// @notice Maximum fee in basis points (5%)
    uint256 public constant MAX_FEE_BPS = 500;

    /// @notice Minimum deadline buffer in seconds (1 minute)
    uint256 public constant MIN_DEADLINE_BUFFER = 60;

    /// @notice Maximum deadline buffer in seconds (1 hour)
    uint256 public constant MAX_DEADLINE_BUFFER = 3600;

    /// @notice EIP-712 version
    string public constant VERSION = "1";

    /// @notice The address of the singleton implementation
    address public immutable SINGLETON;

    // ═══════════════════════════════════════════════════════════════════════════
    //                          STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Token allowlist
    mapping(address => bool) public allowedTokens;

    /// @notice Target contract allowlist
    mapping(address => bool) public allowedTargets;

    /// @notice Selector allowlist per target
    mapping(address => mapping(bytes4 => bool)) public allowedSelectors;

    /// @notice Nonce per user per key (2D nonce mapping)
    /// Key (192 bits) => Sequence (256 bits, though strictly checked against 64 bits of intent)
    mapping(address => mapping(uint192 => uint256)) public nonces;

    /// @notice Global pause state
    bool public paused;

    /// @notice Per-user block state
    mapping(address => bool) public userBlocked;

    /// @notice Treasury address for fee collection
    address public treasury;

    // ═══════════════════════════════════════════════════════════════════════════
    //                            CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the TirraDelegate contract
     * @param _owner The owner address (typically a multisig)
     * @param _treasury The treasury address for fee collection
     */
    constructor(
        address _owner,
        address _treasury
    ) EIP712("TirraDelegate", VERSION) Ownable(_owner) {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        SINGLETON = address(this);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @inheritdoc ITirraDelegate
     */
    function executeBatch(
        Call[] calldata calls,
        Intent calldata intent,
        bytes calldata signature
    ) external nonReentrant returns (bool[] memory results) {
        // ═══════════════════════════════════════════════════════════════════
        //                      VALIDATION PHASE
        // ═══════════════════════════════════════════════════════════════════
        _validateIntent(calls, intent, signature);

        // ═══════════════════════════════════════════════════════════════════
        //                      STATE UPDATE PHASE
        // ═══════════════════════════════════════════════════════════════════

        // Increment nonce (sequence) BEFORE execution (CEI pattern)
        unchecked {
            uint192 key = uint192(intent.nonce >> 64);
            ++nonces[intent.user][key];
        }

        // ═══════════════════════════════════════════════════════════════════
        //                      FEE COLLECTION PHASE
        // ═══════════════════════════════════════════════════════════════════

        if (intent.fee.amount > 0 && intent.fee.token != address(0)) {
            _collectFee(intent.user, intent.fee);
        }

        // ═══════════════════════════════════════════════════════════════════
        //                      EXECUTION PHASE
        // ═══════════════════════════════════════════════════════════════════

        results = _executeCalls(calls);

        // ═══════════════════════════════════════════════════════════════════
        //                    CONSTRAINTS VERIFICATION
        // ═══════════════════════════════════════════════════════════════════

        if (intent.constraints.minOutput > 0) {
            _verifyOutputConstraints(intent.constraints);
        }

        emit IntentExecuted(
            intent.user,
            intent.nonce,
            _hashTypedDataV4(intent.hashIntent()),
            true
        );

        return results;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate intent requirements
     */
    function _validateIntent(
        Call[] calldata calls,
        Intent calldata intent,
        bytes calldata signature
    ) internal view {
        if (ITirraDelegate(SINGLETON).paused()) revert SystemPaused();
        if (ITirraDelegate(SINGLETON).userBlocked(intent.user))
            revert UserIsBlocked();
        if (intent.chainId != block.chainid) revert WrongChainId();
        if (block.timestamp > intent.deadline) revert IntentExpired();
        if (intent.deadline > block.timestamp + MAX_DEADLINE_BUFFER)
            revert DeadlineTooFar();

        uint192 key = uint192(intent.nonce >> 64);
        uint256 seq = uint256(uint64(intent.nonce));
        if (nonces[intent.user][key] != seq) revert InvalidNonce();

        if (calls.length == 0) revert NoCalls();
        if (calls.length > MAX_CALLS) revert TooManyCalls();

        if (calls.hashCalls() != intent.callsHash) revert CallsHashMismatch();
        if (!_verifySignatureInternal(intent, signature))
            revert InvalidSignature();

        uint256 len = calls.length;
        for (uint256 i = 0; i < len; ) {
            _validateCall(calls[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Execute calls in a separate stack frame
     * @param calls calls to execute
     * @return results success results
     */
    function _executeCalls(
        Call[] calldata calls
    ) internal returns (bool[] memory results) {
        uint256 len = calls.length;
        results = new bool[](len);

        for (uint256 i = 0; i < len; ) {
            (bool success, bytes memory returnData) = calls[i].target.call{
                value: calls[i].value
            }(calls[i].data);

            results[i] = success;

            if (!success) {
                revert CallFailed(i, returnData);
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Validate a single call against allowlists
     * @param call The call to validate
     */
    function _validateCall(Call calldata call) internal view {
        // Check target is allowlisted (read from Singleton)
        if (!ITirraDelegate(SINGLETON).allowedTargets(call.target))
            revert TargetNotAllowed();

        // Extract selector from calldata
        if (call.data.length < 4) revert SelectorNotAllowed();
        bytes4 selector = bytes4(call.data[:4]);

        // Check selector is allowlisted for this target (read from Singleton)
        if (
            !ITirraDelegate(SINGLETON).allowedSelectors(call.target, selector)
        ) {
            revert SelectorNotAllowed();
        }
    }

    /**
     * @notice Collect protocol fee from user
     * @param user The user to collect fee from
     * @param fee The fee specification
     */
    function _collectFee(address user, Fee calldata fee) internal {
        // Validate fee token is allowed (read from Singleton)
        if (!ITirraDelegate(SINGLETON).allowedTokens(fee.token))
            revert TokenNotAllowed();

        // Calculate max allowed fee (anti-drain protection)
        uint256 userBalance = IERC20(fee.token).balanceOf(user);
        uint256 maxFee = (userBalance * MAX_FEE_BPS) / 10000;
        if (fee.amount > maxFee) revert FeeTooHigh();

        // Determine recipient (read treasury from Singleton if default)
        address recipient = fee.recipient != address(0)
            ? fee.recipient
            : ITirraDelegate(SINGLETON).treasury();

        // Transfer fee
        // Note: In EIP-7702 context, this call executes as the delegating EOA
        // So we use safeTransfer (not transferFrom) since address(this) IS the user
        IERC20(fee.token).safeTransfer(recipient, fee.amount);

        emit FeeCollected(user, fee.token, fee.amount, recipient);
    }

    /**
     * @notice Verify output constraints are met
     * @param constraints The constraints to verify
     */
    function _verifyOutputConstraints(
        Constraints calldata constraints
    ) internal view {
        if (
            constraints.outputToken != address(0) &&
            constraints.recipient != address(0)
        ) {
            uint256 balance = IERC20(constraints.outputToken).balanceOf(
                constraints.recipient
            );
            if (balance < constraints.minOutput) {
                revert InsufficientOutput();
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the EIP-712 domain separator
     * @return The domain separator
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Get the hash of an intent for signing
     * @param intent The intent to hash
     * @return The EIP-712 typed data hash
     */
    function getIntentHash(
        Intent calldata intent
    ) external view returns (bytes32) {
        return _hashTypedDataV4(intent.hashIntent());
    }

    /**
     * @notice Verify a signature is valid for an intent
     * @param intent The intent
     * @param signature The signature to verify
     * @return True if the signature is valid
     */
    function verifySignature(
        Intent calldata intent,
        bytes calldata signature
    ) external view returns (bool) {
        bytes32 digest = _hashTypedDataV4(intent.hashIntent());
        address signer = digest.recover(signature);
        return signer == intent.user;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @inheritdoc ITirraDelegate
     */
    function setAllowedToken(address token, bool allowed) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        allowedTokens[token] = allowed;
        emit TokenAllowlistUpdated(token, allowed);
    }

    /**
     * @inheritdoc ITirraDelegate
     */
    function setAllowedTarget(address target, bool allowed) external onlyOwner {
        if (target == address(0)) revert ZeroAddress();
        if (allowed && target.code.length == 0) revert NotAContract();
        allowedTargets[target] = allowed;
        emit AllowlistUpdated(target, bytes4(0), allowed);
    }

    /**
     * @inheritdoc ITirraDelegate
     */
    function setAllowedSelector(
        address target,
        bytes4 selector,
        bool allowed
    ) external onlyOwner {
        if (!allowedTargets[target]) revert TargetNotAllowed();
        allowedSelectors[target][selector] = allowed;
        emit AllowlistUpdated(target, selector, allowed);
    }

    /**
     * @inheritdoc ITirraDelegate
     */
    function batchSetAllowedSelectors(
        address target,
        bytes4[] calldata selectors,
        bool allowed
    ) external onlyOwner {
        if (!allowedTargets[target]) revert TargetNotAllowed();
        uint256 length = selectors.length;
        for (uint256 i = 0; i < length; ) {
            allowedSelectors[target][selectors[i]] = allowed;
            emit AllowlistUpdated(target, selectors[i], allowed);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Set the treasury address
     * @param _treasury The new treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
    }

    /**
     * @inheritdoc ITirraDelegate
     */
    function pause() external onlyOwner {
        paused = true;
        emit EmergencyPause(true);
    }

    /**
     * @inheritdoc ITirraDelegate
     */
    function unpause() external onlyOwner {
        paused = false;
        emit EmergencyPause(false);
    }

    /**
     * @inheritdoc ITirraDelegate
     */
    function blockUser(address user) external onlyOwner {
        userBlocked[user] = true;
        emit UserBlocked(user, true);
    }

    /**
     * @inheritdoc ITirraDelegate
     */
    function unblockUser(address user) external onlyOwner {
        userBlocked[user] = false;
        emit UserBlocked(user, false);
    }

    /**
     * @inheritdoc ITirraDelegate
     */
    function recoverTokens(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(recipient, amount);
    }

    /**
     * @notice Internal helper to verify intent signature to reduce stack depth
     */
    function _verifySignatureInternal(
        Intent calldata intent,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(intent.hashIntent());
        address signer = digest.recover(signature);
        return signer == intent.user;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          RECEIVE FUNCTION
    // ═══════════════════════════════════════════════════════════════════════════

    receive() external payable {}
}
