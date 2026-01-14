# Tirra EIP-7702 Smart Contracts

Foundry-based smart contract implementation for the Tirra EIP-7702 Gas-Sponsored Transaction system.

## Overview

The `TirraDelegate` contract acts as a strict execution layer for EOAs that delegate via EIP-7702. It enables gas-sponsored transactions while maintaining security through:

- **EIP-712 Typed Signatures**: Users sign structured intents
- **Strict Allowlists**: Only approved contracts/selectors can be called
- **Sequential Nonces**: Prevents replay attacks
- **Fee Caps**: Maximum 5% fee per transaction
- **Emergency Controls**: Pause and user blocking

## Prerequisites

Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Installation

```bash
# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts

# Copy environment file
cp .env.example .env
# Edit .env with your values
```

## Build

```bash
forge build
```

## Test

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_Deployment

# Run with gas report
forge test --gas-report
```

## Deploy

### Testnet (Base Sepolia)

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export OWNER_ADDRESS=your_multisig_address
export TREASURY_ADDRESS=your_treasury_address

# Deploy
forge script script/Deploy.s.sol:DeployTirraDelegate \
  --rpc-url base_sepolia \
  --broadcast \
  --verify
```

### Mainnet

```bash
forge script script/Deploy.s.sol:DeployTirraDelegate \
  --rpc-url base \
  --broadcast \
  --verify \
  --slow
```

## Contract Architecture

```
src/
├── TirraDelegate.sol           # Main delegate contract
├── interfaces/
│   └── ITirraDelegate.sol      # Interface with types
└── libraries/
    └── IntentHash.sol          # EIP-712 hashing
```

## Security Features

| Feature               | Description                          |
| --------------------- | ------------------------------------ |
| Two-Signature Model   | EIP-7702 auth + EIP-712 intent       |
| Allowlist Enforcement | Targets + selectors must be approved |
| Sequential Nonces     | No gaps, no replay                   |
| Fee Limits            | Max 5% of user balance               |
| Emergency Pause       | Owner can halt all operations        |
| User Blocking         | Block malicious users                |

## License

MIT
