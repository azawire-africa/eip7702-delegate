// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITirraDelegate} from "../interfaces/ITirraDelegate.sol";

/**
 * @title IntentHash
 * @notice Library for EIP-712 hashing of Tirra intents
 * @dev Implements typed structured data hashing per EIP-712
 */
library IntentHash {
    // ═══════════════════════════════════════════════════════════════════════════
    //                            TYPE HASHES
    // ═══════════════════════════════════════════════════════════════════════════

    bytes32 internal constant CALL_TYPEHASH =
        keccak256("Call(address target,uint256 value,bytes data)");

    bytes32 internal constant FEE_TYPEHASH =
        keccak256("Fee(address token,uint256 amount,address recipient)");

    bytes32 internal constant CONSTRAINTS_TYPEHASH =
        keccak256(
            "Constraints(uint256 maxInput,uint256 minOutput,address outputToken,address recipient,uint256 destChainId)"
        );

    bytes32 internal constant INTENT_TYPEHASH =
        keccak256(
            "Intent(address user,uint256 chainId,uint256 nonce,uint256 deadline,bytes32 callsHash,Fee fee,Constraints constraints)Constraints(uint256 maxInput,uint256 minOutput,address outputToken,address recipient,uint256 destChainId)Fee(address token,uint256 amount,address recipient)"
        );

    // ═══════════════════════════════════════════════════════════════════════════
    //                          HASH FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Hash a single Call struct
     * @param call The call to hash
     * @return The EIP-712 hash of the call
     */
    function hashCall(
        ITirraDelegate.Call calldata call
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    CALL_TYPEHASH,
                    call.target,
                    call.value,
                    keccak256(call.data)
                )
            );
    }

    /**
     * @notice Hash an array of Call structs
     * @param calls The calls to hash
     * @return The keccak256 hash of the packed call hashes
     */
    function hashCalls(
        ITirraDelegate.Call[] calldata calls
    ) internal pure returns (bytes32) {
        uint256 length = calls.length;
        bytes32[] memory callHashes = new bytes32[](length);

        for (uint256 i = 0; i < length; ) {
            callHashes[i] = hashCall(calls[i]);
            unchecked {
                ++i;
            }
        }

        return keccak256(abi.encodePacked(callHashes));
    }

    /**
     * @notice Hash a Fee struct
     * @param fee The fee to hash
     * @return The EIP-712 hash of the fee
     */
    function hashFee(
        ITirraDelegate.Fee calldata fee
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(FEE_TYPEHASH, fee.token, fee.amount, fee.recipient)
            );
    }

    /**
     * @notice Hash a Constraints struct
     * @param constraints The constraints to hash
     * @return The EIP-712 hash of the constraints
     */
    function hashConstraints(
        ITirraDelegate.Constraints calldata constraints
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    CONSTRAINTS_TYPEHASH,
                    constraints.maxInput,
                    constraints.minOutput,
                    constraints.outputToken,
                    constraints.recipient,
                    constraints.destChainId
                )
            );
    }

    /**
     * @notice Hash an Intent struct
     * @param intent The intent to hash
     * @return The EIP-712 struct hash of the intent
     */
    function hashIntent(
        ITirraDelegate.Intent calldata intent
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    INTENT_TYPEHASH,
                    intent.user,
                    intent.chainId,
                    intent.nonce,
                    intent.deadline,
                    intent.callsHash,
                    hashFee(intent.fee),
                    hashConstraints(intent.constraints)
                )
            );
    }

    /**
     * @notice Compute the EIP-712 digest for signing
     * @param domainSeparator The EIP-712 domain separator
     * @param intentHash The hash of the intent struct
     * @return The final digest to sign
     */
    function getTypedDataHash(
        bytes32 domainSeparator,
        bytes32 intentHash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, intentHash)
            );
    }
}
