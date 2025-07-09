# DeFi Strategies

Automated portfolio management smart contracts for DeFi protocols with market sentiment-based allocation.

## Overview

This project creates smart contracts for automated USDC portfolio management across various DeFi protocols including AAVE, Lido, Morpho, Uniswap, and others. The system allocates funds based on market conditions (fearful, neutral, bullish, etc.).

### Current Status

**Phase 1: Delta Neutral Strategy** ✅
- Market neutral vault for neutral market conditions
- USDC deposits with automatic allocation
- Spot ETH exposure via AAVE lending
- Delta calculation and position management
- Comprehensive test suite

### Architecture

```
MarketNeutralVault (main contract)
├── PositionManager (delta calculations)
├── AaveStrategy (spot yield)
├── GMXPerpStrategy (short positions) [planned]
└── LidoStakingStrategy (staking rewards) [planned]
```

## Installation

Install dependencies with [Foundry](https://github.com/foundry-rs/foundry):

```bash
forge install
```

## Development

### Compilation

```bash
forge build
```

### Testing

```bash
forge test
```

Run tests with verbosity:
```bash
forge test -vvv
```

### Local Development

This project maintains development logs in `.local/` directory (gitignored). See `.local/development.md` for detailed progress tracking.

## Deployment

Create a `.env` file using `.env.example` as template.

### Dryrun

```bash
forge script script/Deploy.s.sol -f [network]
```

### Live Deployment

```bash
forge script script/Deploy.s.sol -f [network] --verify --broadcast
```

## Contracts

### Core Contracts

- **MarketNeutralVault**: Main vault accepting USDC deposits and managing market neutral positions
- **PositionManager**: Tracks delta exposure and calculates rebalancing needs
- **AaveStrategy**: Handles spot ETH exposure through AAVE lending

### Interfaces

- **IMarketNeutralVault**: Main vault interface
- **IStrategy**: Strategy interface for yield protocols
- **IPositionManager**: Position tracking interface

## Features

### Current Features
- USDC deposits with ERC20 share tokens
- Automatic 50/50 allocation to spot and perpetual strategies
- Delta neutral position management
- Emergency pause functionality
- Comprehensive NatSpec documentation

### Planned Features
- GMX perpetual strategy integration
- DEX integration for USDC→WETH conversions
- Automated rebalancing based on delta thresholds
- Yield harvesting mechanisms
- Sentiment-based allocation adjustments

## Testing

The project includes comprehensive tests covering:
- Vault initialization and configuration
- Deposit/withdrawal mechanics
- Position management
- Emergency scenarios
- Precision attack prevention

## Style Guide

This project follows the Solidity style guide documented in `style-guide.md`, including:
- Lowercase NatSpec documentation
- Custom errors for gas efficiency
- Specific Solidity version (0.8.28)
- Comprehensive inline documentation