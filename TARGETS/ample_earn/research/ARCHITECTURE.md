# Protocol Architecture — Ample Earn

## Overview
Ample Earn is a **prize-linked savings protocol** built on top of **Euler Earn** (ERC-4626 meta-vault).

1. Users deposit USDC into AmpleEarn vaults (ERC-4626 compliant).
2. The vault allocates deposits across Euler lending strategies to generate yield.
3. Yield is pooled and distributed as prizes via **verifiable on-chain randomness**.
4. Users retain full principal ownership with no lockups.
5. Cross-chain prize claims via **LayerZero** (AmpleEarnCrossChainRouter).

## Core Components

### AmplePerspective
- ERC-4626 "perspective" contract that wraps Euler Earn vault logic
- Defines how assets are valued, deposited, and withdrawn
- Implements prize distribution accounting

### AmpleEarnFactory
- Factory pattern — deploys new AmpleEarn vaults via CREATE2 (deterministic)
- Proxy on Monad (upgradeable)
- Constructor: `_owner`, `_evc` (EVC address), `_permit2`, `_perspective`
- Key functions: `createAmpleEarn()`, `setPerspective()`, `isStrategyAllowed()`

### AmpleEarnCrossChainRouter
- LayerZero OApp for cross-chain prize claims
- Constructor: `_endpoint` (LayerZero), `_owner`, `_factory`
- Events: `CrossChainClaimExecuted(srcEid, vault, payoutId, to)`
- Reverts: `InvalidVault`, `NoPeer`, `OnlyPeer`, `InsufficientFee`

### Euler Earn (Underlying)
- ERC-4626 meta-vault per asset (e.g., USDC)
- Up to 30 ERC-4626 strategies per vault
- Supply queue & withdraw queue
- Performance fee up to 50%
- Timelocked risk-increasing actions

## Trust Boundaries
- Euler Earn vaults trusted for yield & accounting
- LayerZero validators trusted for cross-chain messages
- Owner multi-sig trusted for upgrades
- Chainlink oracles trusted for price feeds

## Critical Flows

### Deposit Flow
User → `deposit(USDC)` → AmpleEarn vault → Euler Earn meta-vault → Euler EVK strategies → yield accrual

### Prize Distribution Flow
Euler Earn yield → pooled → on-chain randomness → winner selection → prize claim (cross-chain if needed)

### Cross-Chain Claim Flow
User on Chain A → `AmpleEarnCrossChainRouter.claim()` → LayerZero message → Chain B router → prize payout
