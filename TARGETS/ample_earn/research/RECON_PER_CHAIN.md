# Recon Per Chain — Ample Earn

**Date:** 2026-05-15
**Source:** Source code analysis + Slither static analysis + metadata review

---

## Checklist Summary Per Chain

| Item | Base | Arbitrum | Monad | Katana |
|---|---|---|---|---|
| Proxy architecture | ✅ Immutable | ✅ Immutable | ⚠️ **Factory = Proxy** | ✅ Immutable |
| Oracle dependencies | ✅ None in scope | ✅ None in scope | ✅ None in scope | ✅ None in scope |
| Rebasing assets | ✅ USDC (non-rebasing) | ✅ USDC (non-rebasing) | ✅ USDC (non-rebasing) | ✅ USDC (non-rebasing) |
| Delegatecall usage | ✅ None in scope | ✅ None in scope | ⚠️ Proxy only (OZ) | ✅ None in scope |
| External integrations | ✅ LayerZero, Permit2, EVC, Euler EVK | ✅ Same as Base | ✅ Same + proxy | ✅ Same as Base |
| Flashloan exposure | ⚠️ Low (indirect via EVK) | ⚠️ Low (indirect via EVK) | ⚠️ Low (indirect via EVK) | ⚠️ Low (indirect via EVK) |

---

## 1. Proxy Architecture

### Per Chain

| Chain | AmplePerspective | AmpleEarnFactory | AmpleEarnCrossChainRouter |
|---|---|---|---|
| **Base** | Immutable | Immutable | Immutable |
| **Arbitrum** | Immutable | Immutable | Immutable |
| **Monad** | Immutable | **Proxy (OpenZeppelin)** | Immutable |
| **Katana** | Immutable | Immutable | Immutable |

### Source Verification

- **Monad Factory proxy**: Confirmed in `proxies.json`. This is the only chain where the factory is upgradeable.
- **CREATE2 addresses**: AmplePerspective and AmpleEarnFactory share the same address across Monad/Arbitrum/Katana (deterministic deployment via CREATE2). Base has unique addresses.
- **CrossChainRouter**: Unique address per chain (different LayerZero endpoint/peer configuration).

### Risk Assessment

| Risk | Base | Arbitrum | Monad | Katana |
|---|---|---|---|---|
| Owner upgrades implementation | ✅ Not possible | ✅ Not possible | ⚠️ Via proxy admin | ✅ Not possible |
| Factory logic changed | ✅ Not possible | ✅ Not possible | ⚠️ Owner can change | ✅ Not possible |
| `setPerspective()` backdoor | ⚠️ Via owner | ⚠️ Via owner | ⚠️ Via owner | ⚠️ Via owner |

---

## 2. Oracle Dependencies

### Scope Contracts (zero oracle exposure)

| Contract | Oracle Calls | Analysis |
|---|---|---|
| `AmplePerspective` | None | Pure set membership check (EnumerableSet) |
| `AmpleEarnFactory` | None | CREATE2 deployment + perspective management |
| `AmpleEarnCrossChainRouter` | None | LayerZero messaging + merkle proof verification |

### Underlying Exposure (Euler EVK level — out of scope)

- Euler Earn vaults (strategies) use **Chainlink price feeds** with **TWAP fallback**
- Oracle manipulation in underlying EVK strategies **could** affect:
  - Share price of strategy vaults (`previewRedeem`)
  - `expectedSupplyAssets()` calculation in `StrategyLib`
- **But**: Ample Earn contracts do NOT directly call or rely on any oracle price feed
- Oracle risk exists only if:
  1. An Euler EVK strategy has a manipulated oracle
  2. The strategy share price is affected
  3. This flows through to AmpleEarn's `totalAssets()`

### Per Chain Oracle Config

| Chain | Underlying Asset | Oracle Config | Status |
|---|---|---|---|
| Base | USDC | Chainlink (Euler EVK) | ✅ Not in scope |
| Arbitrum | USDC | Chainlink (Euler EVK) | ✅ Not in scope |
| Monad | USDC | Chainlink (Euler EVK) | ✅ Not in scope |
| Katana | USDC | Unknown (limited liquidity) | ⚠️ Verify |

---

## 3. Rebasing Assets

### Asset Analysis Per Chain

| Chain | Asset | Rebasing? | Fee-on-Transfer? |
|---|---|---|---|
| **Base** | USDC `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | No | No |
| **Arbitrum** | USDC `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | No | No |
| **Monad** | USDC (native bridged) | No | No |
| **Katana** | USDC (native bridged) | No | No |

### Code Verification

- `_deposit()` uses `safeTransferFromWithPermit2(caller, address(this), assets, ...)` — does not check balance before/after
- `_withdraw()` transfers `assets` amount — assumes 1:1 transfer
- **Edge case**: If USDC ever enables fee-on-transfer (like USDT), the vault accounting would break because:
  - `_deposit()` transfers X but receives X - fee → `lastTotalAssets` tracking becomes incorrect
  - `_withdraw()` needs to transfer exact asset amount

### Per Chain Risk

| Chain | Rebasing Risk | Fee-on-Transfer Risk | Confidence |
|---|---|---|---|
| Base | ✅ None | ⚠️ If USDC changes in future | HIGH |
| Arbitrum | ✅ None | ⚠️ Same as Base | HIGH |
| Monad | ✅ None | ⚠️ Same as Base | HIGH |
| Katana | ✅ None | ⚠️ Same as Base | HIGH |

---

## 4. Delegatecall Usage

### Scope Contracts (Source Code)

| Contract | `.delegatecall()` | `.call{value}()` | Other low-level |
|---|---|---|---|
| `AmplePerspective` | 0 | 0 | 0 — pure OZ |
| `AmpleEarnFactory` | 0 | 0 | 0 — pure CREATE2 |
| `AmpleEarnCrossChainRouter` | 0 | **1** (line 130) | 0 |
| `EulerEarn` | 0 | 0 | Uses `address(token).call` in SafeERC20Permit2Lib |

### CrossChainRouter `.call{value}` Analysis (Line 130)

```solidity
if (msg.value > totalValueUsed) {
    (bool success,) = payable(msg.sender).call{value: msg.value - totalValueUsed}("");
    if (!success) revert TransferFailed();
}
```

- Purpose: Refund excess native token after LayerZero fees
- Called after all transfers complete (CEI pattern)
- Uses `nonReentrant` modifier
- **Risk**: MEDIUM, but mitigated by `nonReentrant` + state changes before call

### Monad Proxy Delegatecall

- Not in scope source code — OpenZeppelin `Proxy.sol`
- Implementation (`AmpleEarnFactory`) has no `delegatecall`
- **Risk**: LOW — standard proxy pattern, but owner can upgrade

### Per Chain Summary

| Chain | delegatecall in Scope | Low-level call | Risk Level |
|---|---|---|---|
| Base | 0 | 1 (refund) | LOW |
| Arbitrum | 0 | 1 (refund) | LOW |
| Monad | 0 in scope (+ proxy) | 1 (refund) | LOW-MEDIUM |
| Katana | 0 | 1 (refund) | LOW |

---

## 5. External Integrations

### Integration Map Per Chain

| Integration | Base | Arbitrum | Monad | Katana | Risk |
|---|---|---|---|---|---|
| LayerZero OApp | ✅ | ✅ | ✅ | ✅ | Cross-chain message validity |
| LayerZero EndpointV2 | ✅ | ✅ | ✅ | ✅ | Endpoint liveness |
| Euler EVK Strategies | ✅ | ✅ | ✅ | ✅ | Strategy solvency |
| Permit2 | ✅ | ✅ | ✅ | ✅ | Signature replay |
| EVC | ✅ | ✅ | ✅ | ✅ | Batch auth security |
| OpenZeppelin | ✅ | ✅ | ✅ | ✅ | Standard libs |
| AmpleEarnFactory -> Perspective | ✅ | ✅ | ✅ | ✅ | Perspective trust |

### LayerZero Configuration

| Chain | Router Address | Note |
|---|---|---|
| Base | `0xf132...` | Primary chain |
| Arbitrum | `0xcab6...` | |
| Monad | `0xc908...` | |
| Katana | `0x7beb...` | |

- Each Router has unique peer configuration (`setPeer()` by owner)
- **Risk**: Owner can change peer addresses -> cross-chain message hijack

### Euler EVK Strategies

| Chain | Strategy Vaults | Status |
|---|---|---|
| Base | Multiple (Euler lending vaults) | ✅ Active |
| Arbitrum | Limited | ⚠️ Lower liquidity |
| Monad | Minimal | ⚠️ Early stage |
| Katana | Minimal | ⚠️ Experimental |

### External Call Flow

```
User -> CrossChainRouter.batchCrossChainClaimPayout()
  -> LayerZero EndpointV2._lzSend()
  -> [Destination] Router._lzReceive()
    -> AmpleEarn.claimPayout()
      -> AmplePayoutLib.claimPayout() (merkle verification)
      -> IAmpleEarnReserve.safeTransferPayout()
```

---

## 6. Flashloan Exposure

### Direct Flashloan Risk (None in Scope)

| Contract | Flashloan Function | nonReentrant? | Analysis |
|---|---|---|---|
| `AmplePerspective` | None | N/A | Pure view/set |
| `AmpleEarnFactory` | None | N/A | Deployment + views |
| `AmpleEarnCrossChainRouter` | None | ✅ | LayerZero messaging |
| `EulerEarn` | None (ERC-4626) | ✅ | nonReentrant on deposits/withdrawals |
| `AmpleEarn` | None | ✅ | nonReentrant on claim/setMerkleRoots |

### Indirect Flashloan Risk (Via Euler EVK)

**Scenario**: Flashloan manipulates Euler EVK strategy share price
1. Attacker takes flashloan of USDC
2. Deposits into Euler EVK strategy (affects strategy totalAssets)
3. Strategy share price changes temporarily
4. AmpleEarn vault expectedSupplyAssets() reflects manipulated price
5. Attacker deposits/withdraws from AmpleEarn at manipulated rate
6. Attacker repays flashloan

**Mitigations**: nonReentrant, try/catch in supplyStrategy, EVC context limits

**Remaining Risk**: If EVK strategy allows manipulation and vault has low liquidity

### Per Chain Assessment

| Chain | TVL | Flashloan Capital Required | Liquidity Depth | Risk |
|---|---|---|---|---|
| Base | $4.33M | High ($1M+) | Deep | LOW |
| Arbitrum | $118K | Medium ($50K+) | Medium | LOW-MEDIUM |
| Monad | $4.7K | Low ($2K+) | Low | MEDIUM |
| Katana | $5.7K | Low ($2K+) | Very Low | MEDIUM |

---

## Summary of Per-Chain Risk Profile

| Chain | TVL | Key Risk Factors | Priority |
|---|---|---|---|
| **Base** | $4.33M | Largest TVL; immutable deployment | 🔴 Priority 1 |
| **Arbitrum** | $118K | Lower TVL; standard deployment | 🟡 Priority 2 |
| **Monad** | $4.7K | Proxy risk; very low TVL | 🟡 Priority 3 |
| **Katana** | $5.7K | Experimental chain; low liquidity | 🟢 Priority 4 |
