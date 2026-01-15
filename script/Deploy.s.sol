// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TirraDelegate} from "../src/TirraDelegate.sol";

/**
 * @title DeployTirraDelegate
 * @notice Deployment script for TirraDelegate contract
 */
contract DeployTirraDelegate is Script {
    // Known stablecoin addresses per chain
    mapping(uint256 => address) public USDC;
    mapping(uint256 => address) public USDT;
    mapping(uint256 => address) public cNGN;

    function setUp() public {
        // Base Mainnet (8453)
        USDC[8453] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        cNGN[8453] = 0x46C85152bFe9f96829aA94755D9f915F9B10EF5F;

        // Polygon Mainnet (137)
        USDC[137] = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
        cNGN[137] = 0x52828daa48C1a9A06F37500882b42daf0bE04C3B;

        // Celo Mainnet (42220)
        USDC[42220] = 0xcebA9300f2b948710d2653dD7B07f33A8B32118C;
        cNGN[42220] = 0xE2702Bd97ee33c88c8f6f92DA3B733608aa76F71; // Fixed checksum

        // Lisk L2 (1135)
        USDC[1135] = 0x3b1ac69368eb6447F5db2d4E1641380Fa9e40d29; // Corrected address
        cNGN[1135] = 0x999E3A32eF3F9EAbF133186512b5F29fADB8a816;

        // Assetchain (42420)
        cNGN[42420] = 0x7923C0f6FA3d1BA6EAFCAedAaD93e737Fd22FC4F;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TirraDelegate
        TirraDelegate delegate = new TirraDelegate(owner, treasury);
        console2.log("TirraDelegate deployed at:", address(delegate));

        // Setup initial allowlists based on chain
        uint256 chainId = block.chainid;
        console2.log("Chain ID:", chainId);

        _allowlistToken(delegate, USDC[chainId], "USDC");
        _allowlistToken(delegate, USDT[chainId], "USDT");
        _allowlistToken(delegate, cNGN[chainId], "cNGN");

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Deployment Complete ===");
        console2.log("TirraDelegate:", address(delegate));
        console2.log("Owner:", owner);
        console2.log("Treasury:", treasury);
    }

    function _allowlistToken(
        TirraDelegate delegate,
        address token,
        string memory symbol
    ) internal {
        if (token != address(0)) {
            // Check if address has code
            if (token.code.length == 0) {
                console2.log(
                    string.concat("Skipping ", symbol, ": No code at address"),
                    token
                );
                return;
            }

            delegate.setAllowedToken(token, true);
            delegate.setAllowedTarget(token, true);
            delegate.setAllowedSelector(
                token,
                bytes4(keccak256("transfer(address,uint256)")),
                true
            );
            delegate.setAllowedSelector(
                token,
                bytes4(keccak256("approve(address,uint256)")),
                true
            );
            console2.log(string.concat(symbol, " allowlisted:"), token);
        }
    }
}

/**
 * @title ConfigureRouter
 * @notice Script to add a DEX router to the allowlist
 */
contract ConfigureRouter is Script {
    // Known router addresses
    address constant AERODROME_ROUTER =
        0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address delegateAddress = vm.envAddress("TIRRA_DELEGATE");

        TirraDelegate delegate = TirraDelegate(payable(delegateAddress));

        vm.startBroadcast(deployerPrivateKey);

        // Add Aerodrome router
        delegate.setAllowedTarget(AERODROME_ROUTER, true);

        // Add common swap selectors
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = bytes4(
            keccak256(
                "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"
            )
        );
        selectors[1] = bytes4(
            keccak256(
                "swapExactTokensForTokensSimple(uint256,uint256,address,address,bool,address,uint256)"
            )
        );
        selectors[2] = bytes4(
            keccak256(
                "swapExactETHForTokens(uint256,address[],address,uint256)"
            )
        );
        selectors[3] = bytes4(
            keccak256(
                "swapExactTokensForETH(uint256,uint256,address[],address,uint256)"
            )
        );

        delegate.batchSetAllowedSelectors(AERODROME_ROUTER, selectors, true);

        vm.stopBroadcast();

        console2.log("Router configured:", AERODROME_ROUTER);
    }
}
