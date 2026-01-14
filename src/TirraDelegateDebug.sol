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

contract TirraDelegateDebug is
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

    uint256 public constant MAX_CALLS = 10;
    uint256 public constant MAX_FEE_BPS = 500;
    uint256 public constant MIN_DEADLINE_BUFFER = 60;
    uint256 public constant MAX_DEADLINE_BUFFER = 3600;
    string public constant VERSION = "1";
    address public immutable SINGLETON;

    mapping(address => bool) public allowedTokens;
    mapping(address => bool) public allowedTargets;
    mapping(address => mapping(bytes4 => bool)) public allowedSelectors;
    mapping(address => mapping(uint192 => uint256)) public nonces;
    bool public paused;
    mapping(address => bool) public userBlocked;
    address public treasury;

    constructor(
        address _owner,
        address _treasury
    ) EIP712("TirraDelegate", VERSION) Ownable(_owner) {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        SINGLETON = address(this);
    }

    function executeBatch(
        Call[] calldata calls,
        Intent calldata intent,
        bytes calldata signature
    ) external nonReentrant returns (bool[] memory results) {
        // -----------------------------------------------------------------------
        // ALL CHECKS COMMENTED OUT FOR DEBUGGING
        // -----------------------------------------------------------------------

        // 1. Check system not paused
        // if (ITirraDelegate(SINGLETON).paused()) revert SystemPaused();

        // 2. Check user not blocked
        // if (ITirraDelegate(SINGLETON).userBlocked(intent.user)) revert UserIsBlocked();

        // 4. Validate chain ID
        // if (intent.chainId != block.chainid) revert WrongChainId();

        // 5. Validate deadline
        // if (block.timestamp > intent.deadline) revert IntentExpired();

        // 6. Validate nonce
        // if (intent.nonce != nonces[intent.user]) revert InvalidNonce();

        // 7. Validate calls count
        // if (calls.length == 0) revert NoCalls();

        // 8. Validate calls hash
        // if (calls.hashCalls() != intent.callsHash) revert CallsHashMismatch();

        // 9. Validate signature
        // if (!verifySignature(intent, signature)) revert InvalidSignature();

        // 10. Validate calls allowlist
        // for (uint256 i = 0; i < calls.length; i++) {
        //    _validateCall(calls[i]);
        // }

        // Increment nonce
        unchecked {
            uint192 key = uint192(intent.nonce >> 64);
            ++nonces[intent.user][key];
        }

        // Fee collection
        // if (intent.fee.amount > 0) _collectFee(intent.user, intent.fee);

        // EXECUTION
        uint256 callsLength = calls.length;
        results = new bool[](callsLength);

        for (uint256 i = 0; i < callsLength; ) {
            (bool success, bytes memory returnData) = calls[i].target.call{
                value: calls[i].value
            }(calls[i].data);

            results[i] = success;

            if (!success) {
                // Return data for debug
                if (returnData.length > 0) {
                    assembly {
                        revert(add(32, returnData), mload(returnData))
                    }
                } else {
                    revert CallFailed(i, returnData);
                }
            }

            unchecked {
                ++i;
            }
        }

        emit IntentExecuted(intent.user, intent.nonce, bytes32(0), true);
        return results;
    }

    function _validateCall(Call calldata call) internal view {
        // Disabled logic
    }

    function _collectFee(address user, Fee calldata fee) internal {
        // Disabled logic
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function getIntentHash(
        Intent calldata intent
    ) external view returns (bytes32) {
        return _hashTypedDataV4(intent.hashIntent());
    }

    function verifySignature(
        Intent calldata intent,
        bytes calldata signature
    ) public view returns (bool) {
        bytes32 digest = _hashTypedDataV4(intent.hashIntent());
        address signer = digest.recover(signature);
        return signer == intent.user;
    }

    // Admin functions stubbed
    function setAllowedToken(address, bool) external {}
    function setAllowedTarget(address, bool) external {}
    function setAllowedSelector(address, bytes4, bool) external {}
    function batchSetAllowedSelectors(
        address,
        bytes4[] calldata,
        bool
    ) external {}
    function setTreasury(address) external {}
    function pause() external {}
    function unpause() external {}
    function blockUser(address) external {}
    function unblockUser(address) external {}
    function recoverTokens(address, address, uint256) external {}

    receive() external payable {}
}
