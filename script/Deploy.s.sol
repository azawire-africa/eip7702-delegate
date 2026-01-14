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

    function setUp() public {
        // Base Mainnet
        USDC[8453] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        // Polygon Mainnet
        USDC[137] = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
        USDT[137] = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;

        // Base Sepolia (testnet)
        // Add testnet addresses as needed
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

        // Add USDC if available on this chain
        if (USDC[chainId] != address(0)) {
            delegate.setAllowedToken(USDC[chainId], true);
            delegate.setAllowedTarget(USDC[chainId], true);
            delegate.setAllowedSelector(
                USDC[chainId],
                bytes4(keccak256("transfer(address,uint256)")),
                true
            );
            delegate.setAllowedSelector(
                USDC[chainId],
                bytes4(keccak256("approve(address,uint256)")),
                true
            );
            console2.log("USDC allowlisted:", USDC[chainId]);
        }

        // Add USDT if available on this chain
        if (USDT[chainId] != address(0)) {
            delegate.setAllowedToken(USDT[chainId], true);
            delegate.setAllowedTarget(USDT[chainId], true);
            delegate.setAllowedSelector(
                USDT[chainId],
                bytes4(keccak256("transfer(address,uint256)")),
                true
            );
            delegate.setAllowedSelector(
                USDT[chainId],
                bytes4(keccak256("approve(address,uint256)")),
                true
            );
            console2.log("USDT allowlisted:", USDT[chainId]);
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Deployment Complete ===");
        console2.log("TirraDelegate:", address(delegate));
        console2.log("Owner:", owner);
        console2.log("Treasury:", treasury);
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
