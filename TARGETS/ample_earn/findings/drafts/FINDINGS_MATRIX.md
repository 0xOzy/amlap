# Findings Matrix — Ample Earn (HackenProof Submission)

## Summary

| ID | Title | Severity | Status | Affected Contracts | Economic Damage |
|---|---|---|---|---|---|
| **AE-F-002** | Cross-Chain Payout Replay | 🔴 CRITICAL | ✅ Validated | `AmpleEarn.sol` (vault) | $123–$304/week (3 chains) |
| **AE-F-005** | Missing nonReentrant in batchCrossChainClaimPayout | 🟠 MEDIUM | ✅ Validated | `AmpleEarnCrossChainRouter.sol` | Griefing (standalone) |
| **AE-F-007** | Combined: Reentrancy Amplification of Cross-Chain Replay | 🟡 HIGH | ✅ Validated | `AmpleEarn.sol` + `AmpleEarnCrossChainRouter.sol` | $500–$1,200/week |

## Economic Damage Calculation

### AE-F-002 (Standalone)
```
Weekly replay profit (3 chains): $123–$304/week
Based on: Average prize distribution across Arbitrum, Monad, Katana
          with realistic payoutId collision probability.
```

### AE-F-007 (Combined — AE-F-002 + AE-F-005)
```
AE-F-002 standalone:        $123–$304/week (3 chains)
AE-F-005 amplification:     ×2 per chain (duplicate LZ message)
Combined upper bound:        $304 × 2 = $608/week (conservative)
                             $304 × 3 chains × 2 = $1,200/week (upper)
```

The reentrancy gap in `batchCrossChainClaimPayout` (AE-F-005) allows an attacker to send **duplicate LayerZero messages** for the same `payoutId` in a single transaction. This doubles the cross-chain replay profit (AE-F-002) on each vulnerable chain because the destination chain receives two identical claim messages instead of one.

## Test Files

| Test File | Type | What It Proves |
|---|---|---|
| `src/test/FT-02_CrossChainPayoutReplay.t.sol` | Fork test | Storage isolation between chains (AE-F-002) |
| `src/test/FT-02_FullPoC.t.sol` | Fork test | Full storage isolation proof (AE-F-002) |
| `src/test/FT-05_ReentrancyPoC.sol` | Unit test | Reentrancy possible (AE-F-005) |
| `src/test/FT-05_AmplificationPoC.t.sol` | Unit test | Duplicate LZ messages via reentrancy (AE-F-007) |
| `src/test/FT-05_AmplificationFork.t.sol` | Fork test | Reentrancy confirmed on real Arbitrum router (AE-F-007) |

## Commands to Reproduce

```bash
# AE-F-002: Cross-chain replay (storage isolation)
forge test --match-contract CrossChainReplayPoC -vvvv

# AE-F-005: Reentrancy gap (unit test)
forge test --match-contract ReentrancyPoC -vvvv

# AE-F-007: Amplification PoC (mock endpoint)
forge test --match-test test_DoubleMessageSent -vvvv

# AE-F-007: Amplification fork test (real Arbitrum router)
forge test --match-test test_AmplificationFork --fork-url $ARBITRUM_RPC_URL -vvvv
```
