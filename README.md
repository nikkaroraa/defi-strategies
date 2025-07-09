# DeFi Strategies

Smart contracts for automated USDC portfolio management across DeFi protocols.

> ⚠️ **Warning**: This project is in active development and contracts are unaudited. Do not use with real funds.

## Overview

Automated portfolio management that allocates USDC deposits across various DeFi protocols based on market conditions. Currently implementing delta neutral strategies for neutral market conditions.

## Development

### Installation

```bash
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy

Create a `.env` file using `.env.example` as template.

```bash
# Dryrun
forge script script/Deploy.s.sol -f [network]

# Live deployment
forge script script/Deploy.s.sol -f [network] --verify --broadcast
```