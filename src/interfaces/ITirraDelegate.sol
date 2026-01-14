// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ITirraDelegate
 * @notice Interface for the Tirra EIP-7702 Delegate Contract
 * @dev This contract acts as a strict execution layer for EOAs that delegate via EIP-7702
 */
interface ITirraDelegate {
    // ═══════════════════════════════════════════════════════════════════════════
    //                              STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Single call to execute
    struct Call {
        address target; // Contract to call (must be allowlisted)
        uint256 value; // Native token value (usually 0 for sponsored tx)
        bytes data; // Calldata (first 4 bytes must be allowlisted selector)
    }

    /// @notice Protocol fee specification
    struct Fee {
        address token; // ERC-20 token for fee (address(0) = no fee)
        uint256 amount; // Fee amount in token units
        address recipient; // Fee recipient (usually Tirra treasury)
    }

    /// @notice Output constraints for swaps/bridges
    struct Constraints {
        uint256 maxInput; // Maximum input amount (slippage protection)
        uint256 minOutput; // Minimum output amount (slippage protection)
        address outputToken; // Expected output token address
        address recipient; // Final recipient of output
        uint256 destChainId; // Destination chain (0 = same chain)
    }

    /// @notice Full intent signed by user
    struct Intent {
        address user; // EOA address
        uint256 chainId; // Chain ID (replay protection)
        uint256 nonce; // Sequential nonce
        uint256 deadline; // Unix timestamp expiry
        bytes32 callsHash; // keccak256 of encoded calls
        Fee fee; // Protocol fee
        Constraints constraints; // Output constraints
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when an intent is successfully executed
    event IntentExecuted(
        address indexed user,
        uint256 indexed nonce,
        bytes32 indexed intentHash,
        bool success
    );

    /// @notice Emitted when a protocol fee is collected
    event FeeCollected(
        address indexed user,
        address indexed token,
        uint256 amount,
        address recipient
    );

    /// @notice Emitted when allowlist is updated
    event AllowlistUpdated(
        address indexed target,
        bytes4 selector,
        bool allowed
    );

    /// @notice Emitted when token allowlist is updated
    event TokenAllowlistUpdated(address indexed token, bool allowed);

    /// @notice Emitted when emergency pause state changes
    event EmergencyPause(bool paused);

    /// @notice Emitted when a user is blocked/unblocked
    event UserBlocked(address indexed user, bool blocked);

    // ═══════════════════════════════════════════════════════════════════════════
    //                              ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error SystemPaused();
    error UserIsBlocked();
    error UnauthorizedCaller();
    error WrongChainId();
    error IntentExpired();
    error DeadlineTooFar();
    error InvalidNonce();
    error NoCalls();
    error TooManyCalls();
    error CallsHashMismatch();
    error InvalidSignature();
    error TargetNotAllowed();
    error SelectorNotAllowed();
    error TokenNotAllowed();
    error CallFailed(uint256 index, bytes reason);
    error InsufficientOutput();
    error FeeTooHigh();
    error FeeTransferFailed();
    error ZeroAddress();
    error NotAContract();

    // ═══════════════════════════════════════════════════════════════════════════
    //                          CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Execute a batch of calls on behalf of a delegating EOA
     * @param calls Array of calls to execute
     * @param intent Signed intent containing constraints
     * @param signature EIP-712 signature over the intent
     * @return results Array of success status for each call
     */
    function executeBatch(
        Call[] calldata calls,
        Intent calldata intent,
        bytes calldata signature
    ) external returns (bool[] memory results);

    // ═══════════════════════════════════════════════════════════════════════════
    //                          VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get the current nonce for a user and key
    function nonces(address user, uint192 key) external view returns (uint256);

    /// @notice Check if the system is paused
    function paused() external view returns (bool);

    /// @notice Check if a user is blocked
    function userBlocked(address user) external view returns (bool);

    /// @notice Get the treasury address
    function treasury() external view returns (address);

    /// @notice Check if a token is in the allowlist
    function allowedTokens(address token) external view returns (bool);

    /// @notice Check if a target is in the allowlist
    function allowedTargets(address target) external view returns (bool);

    /// @notice Check if a selector is allowed for a target
    function allowedSelectors(
        address target,
        bytes4 selector
    ) external view returns (bool);

    /// @notice Get the EIP-712 domain separator
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    // ═══════════════════════════════════════════════════════════════════════════
    //                          ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Add or remove a token from the allowlist
    function setAllowedToken(address token, bool allowed) external;

    /// @notice Add or remove a target from the allowlist
    function setAllowedTarget(address target, bool allowed) external;

    /// @notice Add or remove a selector for a specific target
    function setAllowedSelector(
        address target,
        bytes4 selector,
        bool allowed
    ) external;

    /// @notice Batch update selectors for a target
    function batchSetAllowedSelectors(
        address target,
        bytes4[] calldata selectors,
        bool allowed
    ) external;

    /// @notice Pause all operations
    function pause() external;

    /// @notice Unpause operations
    function unpause() external;

    /// @notice Block a specific user
    function blockUser(address user) external;

    /// @notice Unblock a user
    function unblockUser(address user) external;

    /// @notice Recover tokens accidentally sent to this contract
    function recoverTokens(
        address token,
        address recipient,
        uint256 amount
    ) external;
}
