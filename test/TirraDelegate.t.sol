// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {TirraDelegate} from "../src/TirraDelegate.sol";
import {ITirraDelegate} from "../src/interfaces/ITirraDelegate.sol";
import {IntentHash} from "../src/libraries/IntentHash.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

/**
 * @title TirraDelegateTest
 * @notice Comprehensive test suite for TirraDelegate contract
 */
contract TirraDelegateTest is Test {
    using IntentHash for ITirraDelegate.Call[];
    using IntentHash for ITirraDelegate.Intent;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 constant USER_PRIVATE_KEY =
        0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    uint256 constant OWNER_PRIVATE_KEY =
        0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              STATE
    // ═══════════════════════════════════════════════════════════════════════════

    TirraDelegate public delegate;
    ERC20Mock public usdc;
    ERC20Mock public usdt;

    address public owner;
    address public user;
    address public treasury;
    address public recipient;
    address public relayer;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        owner = vm.addr(OWNER_PRIVATE_KEY);
        user = vm.addr(USER_PRIVATE_KEY);
        treasury = makeAddr("treasury");
        recipient = makeAddr("recipient");
        relayer = makeAddr("relayer");

        // Deploy mock tokens
        usdc = new ERC20Mock("USD Coin", "USDC", 6);
        usdt = new ERC20Mock("Tether USD", "USDT", 6);

        // Deploy delegate contract
        vm.prank(owner);
        delegate = new TirraDelegate(owner, treasury);

        // Setup allowlists
        vm.startPrank(owner);
        delegate.setAllowedToken(address(usdc), true);
        delegate.setAllowedToken(address(usdt), true);
        delegate.setAllowedTarget(address(usdc), true);
        delegate.setAllowedTarget(address(usdt), true);
        delegate.setAllowedSelector(
            address(usdc),
            IERC20.transfer.selector,
            true
        );
        delegate.setAllowedSelector(
            address(usdc),
            IERC20.approve.selector,
            true
        );
        delegate.setAllowedSelector(
            address(usdt),
            IERC20.transfer.selector,
            true
        );
        vm.stopPrank();

        // Fund user with tokens
        usdc.mint(user, 10000e6);
        usdt.mint(user, 10000e6);

        // Approve delegate to spend user's tokens (for fee collection)
        vm.prank(user);
        usdc.approve(address(delegate), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function _createTransferCall(
        address token,
        address to,
        uint256 amount
    ) internal pure returns (ITirraDelegate.Call memory) {
        return
            ITirraDelegate.Call({
                target: token,
                value: 0,
                data: abi.encodeWithSelector(
                    IERC20.transfer.selector,
                    to,
                    amount
                )
            });
    }

    function _createIntent(
        ITirraDelegate.Call[] memory calls,
        uint256 nonce,
        uint256 deadline,
        uint256 feeAmount
    ) internal view returns (ITirraDelegate.Intent memory) {
        return
            ITirraDelegate.Intent({
                user: user,
                chainId: block.chainid,
                nonce: nonce,
                deadline: deadline,
                callsHash: _hashCallsMemory(calls),
                fee: ITirraDelegate.Fee({
                    token: feeAmount > 0 ? address(usdc) : address(0),
                    amount: feeAmount,
                    recipient: treasury
                }),
                constraints: ITirraDelegate.Constraints({
                    maxInput: 0,
                    minOutput: 0,
                    outputToken: address(0),
                    recipient: address(0),
                    destChainId: 0
                })
            });
    }

    function _hashCallsMemory(
        ITirraDelegate.Call[] memory calls
    ) internal pure returns (bytes32) {
        bytes32[] memory callHashes = new bytes32[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            callHashes[i] = keccak256(
                abi.encode(
                    keccak256("Call(address target,uint256 value,bytes data)"),
                    calls[i].target,
                    calls[i].value,
                    keccak256(calls[i].data)
                )
            );
        }

        return keccak256(abi.encodePacked(callHashes));
    }

    function _signIntent(
        ITirraDelegate.Intent memory intent,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Intent(address user,uint256 chainId,uint256 nonce,uint256 deadline,bytes32 callsHash,Fee fee,Constraints constraints)Constraints(uint256 maxInput,uint256 minOutput,address outputToken,address recipient,uint256 destChainId)Fee(address token,uint256 amount,address recipient)"
                ),
                intent.user,
                intent.chainId,
                intent.nonce,
                intent.deadline,
                intent.callsHash,
                _hashFee(intent.fee),
                _hashConstraints(intent.constraints)
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                delegate.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _hashFee(
        ITirraDelegate.Fee memory fee
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "Fee(address token,uint256 amount,address recipient)"
                    ),
                    fee.token,
                    fee.amount,
                    fee.recipient
                )
            );
    }

    function _hashConstraints(
        ITirraDelegate.Constraints memory constraints
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "Constraints(uint256 maxInput,uint256 minOutput,address outputToken,address recipient,uint256 destChainId)"
                    ),
                    constraints.maxInput,
                    constraints.minOutput,
                    constraints.outputToken,
                    constraints.recipient,
                    constraints.destChainId
                )
            );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          DEPLOYMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Deployment() public view {
        assertEq(delegate.owner(), owner);
        assertEq(delegate.treasury(), treasury);
        assertFalse(delegate.paused());
    }

    function test_DeploymentRevertsWithZeroTreasury() public {
        vm.expectRevert(ITirraDelegate.ZeroAddress.selector);
        new TirraDelegate(owner, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          ALLOWLIST TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetAllowedToken() public {
        address newToken = makeAddr("newToken");

        vm.prank(owner);
        delegate.setAllowedToken(newToken, true);

        assertTrue(delegate.allowedTokens(newToken));
    }

    function test_SetAllowedTokenRevertsIfNotOwner() public {
        address newToken = makeAddr("newToken");

        vm.prank(user);
        vm.expectRevert();
        delegate.setAllowedToken(newToken, true);
    }

    function test_SetAllowedTarget() public {
        // Deploy a mock contract to use as target
        ERC20Mock newTarget = new ERC20Mock("Test", "TEST", 18);

        vm.prank(owner);
        delegate.setAllowedTarget(address(newTarget), true);

        assertTrue(delegate.allowedTargets(address(newTarget)));
    }

    function test_SetAllowedTargetRevertsForEOA() public {
        address eoaTarget = makeAddr("eoaTarget");

        vm.prank(owner);
        vm.expectRevert(ITirraDelegate.NotAContract.selector);
        delegate.setAllowedTarget(eoaTarget, true);
    }

    function test_SetAllowedSelector() public {
        bytes4 newSelector = bytes4(keccak256("newFunction()"));

        vm.prank(owner);
        delegate.setAllowedSelector(address(usdc), newSelector, true);

        assertTrue(delegate.allowedSelectors(address(usdc), newSelector));
    }

    function test_BatchSetAllowedSelectors() public {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = bytes4(keccak256("function1()"));
        selectors[1] = bytes4(keccak256("function2()"));
        selectors[2] = bytes4(keccak256("function3()"));

        vm.prank(owner);
        delegate.batchSetAllowedSelectors(address(usdc), selectors, true);

        for (uint256 i = 0; i < selectors.length; i++) {
            assertTrue(delegate.allowedSelectors(address(usdc), selectors[i]));
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          PAUSE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Pause() public {
        vm.prank(owner);
        delegate.pause();

        assertTrue(delegate.paused());
    }

    function test_Unpause() public {
        vm.startPrank(owner);
        delegate.pause();
        delegate.unpause();
        vm.stopPrank();

        assertFalse(delegate.paused());
    }

    function test_PauseRevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        delegate.pause();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          USER BLOCKING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_BlockUser() public {
        vm.prank(owner);
        delegate.blockUser(user);

        assertTrue(delegate.userBlocked(user));
    }

    function test_UnblockUser() public {
        vm.startPrank(owner);
        delegate.blockUser(user);
        delegate.unblockUser(user);
        vm.stopPrank();

        assertFalse(delegate.userBlocked(user));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          NONCE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_InitialNonceIsZero() public view {
        assertEq(delegate.nonces(user, 0), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          SIGNATURE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_VerifySignature() public {
        ITirraDelegate.Call[] memory calls = new ITirraDelegate.Call[](1);
        calls[0] = _createTransferCall(address(usdc), recipient, 100e6);

        ITirraDelegate.Intent memory intent = _createIntent(
            calls,
            0,
            block.timestamp + 300,
            0
        );

        bytes memory signature = _signIntent(intent, USER_PRIVATE_KEY);

        assertTrue(delegate.verifySignature(intent, signature));
    }

    function test_VerifySignatureFailsWithWrongSigner() public {
        ITirraDelegate.Call[] memory calls = new ITirraDelegate.Call[](1);
        calls[0] = _createTransferCall(address(usdc), recipient, 100e6);

        ITirraDelegate.Intent memory intent = _createIntent(
            calls,
            0,
            block.timestamp + 300,
            0
        );

        // Sign with wrong key
        bytes memory signature = _signIntent(intent, OWNER_PRIVATE_KEY);

        assertFalse(delegate.verifySignature(intent, signature));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          DOMAIN SEPARATOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_DomainSeparator() public view {
        bytes32 domainSeparator = delegate.DOMAIN_SEPARATOR();
        assertNotEq(domainSeparator, bytes32(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          RECOVER TOKENS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_RecoverTokens() public {
        // Send some tokens to the delegate contract
        usdc.mint(address(delegate), 1000e6);

        uint256 recipientBalanceBefore = usdc.balanceOf(recipient);

        vm.prank(owner);
        delegate.recoverTokens(address(usdc), recipient, 1000e6);

        assertEq(usdc.balanceOf(recipient), recipientBalanceBefore + 1000e6);
    }

    function test_RecoverTokensRevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        delegate.recoverTokens(address(usdc), recipient, 1000e6);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          TREASURY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(owner);
        delegate.setTreasury(newTreasury);

        assertEq(delegate.treasury(), newTreasury);
    }

    function test_SetTreasuryRevertsWithZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ITirraDelegate.ZeroAddress.selector);
        delegate.setTreasury(address(0));
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                              HELPER INTERFACE
// ═══════════════════════════════════════════════════════════════════════════════

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
