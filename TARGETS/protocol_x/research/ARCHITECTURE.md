# Protocol Architecture

## Overview

Users deposit collateral into Vault.

Vault issues shares representing ownership.

OracleRouter determines collateral valuation.

Borrowing power derived from collateral value.

Liquidation engine handles unhealthy positions.

## Core Components

- Vault
- LendingPool
- OracleRouter
- LiquidationManager
- RewardDistributor

## Trust Boundaries

- Oracle system trusted
- Timelock trusted
- Upgrade admin trusted

## Critical Flows

Deposit Flow:
User -> Vault -> Share Mint

Borrow Flow:
Collateral -> Oracle -> Debt Issuance

Liquidation Flow:
Health Check -> Liquidator -> Collateral Seizure
