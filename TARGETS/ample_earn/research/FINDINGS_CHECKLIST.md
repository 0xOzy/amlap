# Findings Checklist — Ample Earn

**Date:** 2026-05-15
**Target:** Prize-linked savings protocol on Euler Earn (HackenProof bounty, up to $20K Critical)
**Scope:** AmplePerspective, AmpleEarnFactory, AmpleEarnCrossChainRouter — 12 contracts (3 types × 4 chains)
**Status:** Recon phase complete — Static analysis done — Pending fork validation

---

## Status Legend

| Symbol | Meaning |
|---|---|
| ✅ **Verified** | Confirmed via source analysis, on-chain verification, or fork test |
| ⚠️ **Needs Investigation** | Indication exists but requires fork test or on-chain validation |
| ❌ **Rejected** | Proven not exploitable after validation |
| ❓ **Unknown** | Insufficient information to assess |
| 🔴 **Critical** | Direct fund loss / protocol insolvency |
| 🟡 **High** | Significant fund loss or privilege escalation |
| 🟠 **Medium** | Limited fund loss or specific conditions |
| 🟢 **Low** | Informational, gas optimization, or edge case |

---

## A. IN-SCOPE VULNERABILITY FINDINGS

### A1. ERC-4626 Share Inflation via Donation Attack

| Field | Value |
|---|---|
| **ID** | `AE-F-001` |
| **Category** | ERC-4626 Accounting |
| **Contracts** | `AmpleEarn` (via `EulerEarn` — underlying, but impact is in scope) |
| **Chains** | All (🔴 Base priority: $4.33M TVL) |
| **Status** | ⚠️ **Needs Fork Test** |
| **Confidence** | **MEDIUM** |
| **Severity** | 🟡 **High** (up to loss of deposit value for subsequent depositors) |

**Description:**
Standard ERC-4626 donation attack: attacker donates USDC directly to vault before victim deposits, inflating share price. `EulerEarn` uses OZ `ERC4626._deposit()` which calculates shares as `assets * totalSupply() / totalAssets()` — no virtual shares or offset mechanism.

**Requirements:**
- ✅ Vault accepts direct token transfers (confirmed: USDC to vault address)
- ✅ Exchange rate depends on `balanceOf(vault)` — `totalAssets()` in OZ ERC4626 uses `asset.balanceOf(address(this))`
- ❓ Does `AmpleEarn.totalAssets()` override this? (needs source verification)

**Validation Required:**
- [ ] Fork test: Call `USDC.transfer(vault, 1000e6)` then `deposit(1e6)` — check shares received
- [ ] Check if `AmpleEarn` or `EulerEarn` overrides `totalAssets()` with internal accounting

**Slither Reference:** `arbitrary-send-erc20` in OZ `ERC4626._deposit()`

---

### A2. Cross-Chain Payout Claim Replay

| Field | Value |
|---|---|
| **ID** | `AE-F-002` |
| **Category** | Cross-Chain Replay |
| **Contracts** | `AmpleEarnCrossChainRouter` |
| **Chains** | All (all chains share same source code) |
| **Status** | ⚠️ **Needs Investigation** |
| **Confidence** | **MEDIUM** |
| **Severity** | 🟡 **High** (double claims, prize pool drain) |

**Description:**
`payoutId` tracking may be per-chain rather than globally unique. If a winner's `payoutId` is processed on chain A, the same `payoutId` might be claimable on chain B if the merkle root is shared across chains.

**Key Findings:**
- `_executeClaims()` checks `IAmpleEarn(vault).isPayoutClaimed(payoutId)` — this is on the **destination** vault
- ✅ `CrossChainClaimExecuted` event includes `payoutId` — history on source chain only
- ❓ Does `payoutId` uniqueness depend on `vault + payoutId` composite key?
- ❓ Are merkle roots shared across chains? If yes, same proof works on multiple chains

**Attack Path:**
1. Winner submits claim on Base → `batchCrossChainClaimPayout()` sends LZ message to Arbitrum
2. Winner submits SAME `payoutId` via different path (or LZ message replay)
3. If `isPayoutClaimed()` checked on destination chain only, same payout can be claimed N times

**Validation Required:**
- [ ] Trace `payoutId` → `isPayoutClaimed()` storage slot — is it vault-specific OR global?
- [ ] Check if same merkle root deployed on multiple chains
- [ ] Fork test: Claim payoutId on chain A, try to claim same on chain B

---

### A3. msg.value Loop Overpayment — No Refund Per Iteration

| Field | Value |
|---|---|
| **ID** | `AE-F-003` |
| **Category** | Accounting / Fund Loss |
| **Contracts** | `AmpleEarnCrossChainRouter` (line 89-133) |
| **Chains** | All |
| **Status** | ✅ **Verified via Source** |
| **Confidence** | **HIGH** |
| **Severity** | 🟠 **MEDIUM** |

**Slither:** `msg-value-loop` (HIGH/Medium)

**Description:**
`batchCrossChainClaimPayout()` accumulates `totalValueUsed` in a loop and only refunds excess at the end. Each individual iteration validates `totalValueUsed + fee.nativeFee > msg.value` — correct if user sends enough native token for ALL destinations. If one `quote()` returns higher fee mid-batch, the iteration fails.

**Edge Cases:**
- User must compute exact total across all destinations — error prone
- EOA `msg.sender` receives refund, but what if `msg.sender` is a contract?

**Validation Required:**
- [ ] Verify refund address is `msg.sender` (not a forwarded call context)
- [ ] Test mid-batch failure scenario

---

### A4. Uninitialized Local Variable — `totalValueUsed`

| Field | Value |
|---|---|
| **ID** | `AE-F-004` |
| **Category** | Accounting |
| **Contracts** | `AmpleEarnCrossChainRouter` (line 98) |
| **Chains** | All |
| **Status** | ✅ **Verified via Source** |
| **Confidence** | **HIGH** |
| **Severity** | 🟠 **MEDIUM** |

**Slither:** `uninitialized-local` (MEDIUM/Medium)

**Description:**
```solidity
uint256 totalValueUsed;  // Line 98 — never initialized to 0
```
In Solidity 0.8.26, uninitialized locals default to 0. If `_lzSend()` re-enters (unlikely), `totalValueUsed` could behave unexpectedly. Low practical risk but code quality concern.

---

### A5. batchCrossChainClaimPayout — nonReentrant Missing

| Field | Value |
|---|---|
| **ID** | `AE-F-005` |
| **Category** | Reentrancy |
| **Contracts** | `AmpleEarnCrossChainRouter` |
| **Chains** | All |
| **Status** | ✅ **Verified via Source** |
| **Confidence** | **MEDIUM** |
| **Severity** | 🟠 **MEDIUM** |

**Description:**
`batchCrossChainClaimPayout()` does NOT have `nonReentrant`. It performs:
1. External calls to `ILayerZeroEndpointV2._lzSend()`
2. Low-level `.call{value}` to `msg.sender` (refund at line 130)

The refund call is the reentrancy vector — if `msg.sender` is a contract, it could re-enter.

**Comparison:** `_executeClaims()` (line 177) IS called within `_lzReceive()` which has `nonReentrant`. But the caller-facing `batchCrossChainClaimPayout()` is NOT protected.

**Validation Required:**
- [ ] Test: Deploy attacker contract → call batchCrossChainClaimPayout → receive refund → re-enter

---

### A6. Cross-Chain Router — Redundant `_guid` / `_executor` / `_extraData`

| Field | Value |
|---|---|
| **ID** | `AE-F-006` |
| **Category** | Code Quality |
| **Contracts** | `AmpleEarnCrossChainRouter` (line 160-162) |
| **Chains** | All |
| **Status** | ✅ **Verified via Source** |
| **Confidence** | **HIGH** |
| **Severity** | 🟢 **Low** |

**Slither:** `redundant-statements` (INFORMATIONAL/High)

**Description:**
In `_lzReceive()`, three parameters (`_guid`, `_executor`, `_extraData`) are declared but never used. The unused `_guid` (LayerZero message GUID) is notable — it could serve as a unique message identifier for replay protection, but it's discarded.

---

## B. STATIC ANALYSIS FINDINGS (Slither)

### B1. Scope Contract Findings Summary

| ID | Detector | Impact | Confidence | Contract | Line | Description |
|---|---|---|---|---|---|---|
| `AE-S-001` | `arbitrary-send-erc20` | HIGH | HIGH | `SafeERC20Permit2Lib` | 50 | Arbitrary `from` in `transferFrom` |
| `AE-S-002` | `msg-value-loop` | HIGH | MEDIUM | `CrossChainRouter` | 89 | `msg.value` in loop |
| `AE-S-003` | `msg-value-loop` | HIGH | MEDIUM | `CrossChainRouter` | 208 | `msg.value` in `_payNative` |
| `AE-S-004` | `uninitialized-local` | MEDIUM | MEDIUM | `CrossChainRouter` | 98 | `totalValueUsed` |
| `AE-S-005` | `uninitialized-local` | MEDIUM | MEDIUM | `EulerEarn` | 759 | `realTotalAssets` |
| `AE-S-006` | `uninitialized-local` | MEDIUM | MEDIUM | `SafeERC20Permit2Lib` | 38 | `permit2Amount` |
| `AE-S-007` | `uninitialized-local` | MEDIUM | MEDIUM | `ReallocateLib` | 43 | `totalSupplied` |
| `AE-S-008` | `uninitialized-local` | MEDIUM | MEDIUM | `ReallocateLib` | 57 | `shares` |
| `AE-S-009` | `uninitialized-local` | MEDIUM | MEDIUM | `ReallocateLib` | 44 | `totalWithdrawn` |
| `AE-S-010` | `unused-return` | MEDIUM | MEDIUM | `SafeERC20Permit2Lib` | 43 | Permit2 return value ignored |
| `AE-S-011` | `unused-return` | MEDIUM | MEDIUM | `StrategyLib` | 56 | `suppliedShares` ignored |
| `AE-S-012` | `shadowing-local` | LOW | HIGH | `EulerEarn` | 453 | `owner` shadows Ownable |
| `AE-S-013` | `shadowing-local` | LOW | HIGH | `CrossChainRouter` | 59 | `_owner` shadows Ownable |
| `AE-S-014` | `shadowing-local` | LOW | HIGH | `AmpleEarn` | 93 | `owner` shadows Ownable |
| `AE-S-015` | `shadowing-local` | LOW | HIGH | `AmpleEarnFactory` | 60 | `_owner` shadows Ownable |
| `AE-S-016` | `low-level-calls` | INFO | HIGH | `CrossChainRouter` | 130 | `.call{value}` to `msg.sender` |
| `AE-S-017` | `low-level-calls` | INFO | HIGH | `SafeERC20Permit2Lib` | 55 | `.call` for approve |
| `AE-S-018` | `reentrancy-events` | LOW | MEDIUM | `CrossChainRouter` | 177 | Event after external call |
| `AE-S-019` | `timestamp` | LOW | MEDIUM | `EulerEarn` | 817 | `block.timestamp` for timelock |
| `AE-S-020` | `redundant-statements` | INFO | HIGH | `CrossChainRouter` | 160-162 | Unused LZ params |
| `AE-S-021` | `cache-array-length` | OPT | HIGH | `EulerEarn` | 540,705,760 | Array length in loops |

### B2. Key False Positives / Mitigated

| Detector | Reason |
|---|---|
| `arbitrary-send-erc20` in ERC4626 | Standard ERC-4626 pattern; caller validated by EVC |
| `incorrect-exp` in Math.sol | OZ library; uses `^2` intentionally for gas |
| `incorrect-return` in EVCUtil | Standard EVC assembly pattern |
| `shadowing-local` in constructors | Common Solidity pattern; no functional impact |

---

## C. CONFIGURATION / DEPLOYMENT FINDINGS

### C1. Monad Factory on Proxy

| Field | Value |
|---|---|
| **ID** | `AE-C-001` |
| **Category** | Upgradeability |
| **Contracts** | `AmpleEarnFactory` (Monad only) |
| **Chain** | ⚠️ **Monad** |
| **Status** | ✅ **Verified** |
| **Confidence** | **HIGH** |
| **Severity** | 🟠 **MEDIUM** (requires multi-sig compromise) |

**Finding:**
`AmpleEarnFactory` on Monad is behind an OpenZeppelin Transparent Proxy. No other chain has a proxy for any scope contract.

**Impact:**
- Owner can upgrade factory implementation → arbitrary CREATE2 deployments
- New implementation can set malicious perspective → all future vaults use fake strategy validation
- TVL on Monad is only $4.7K, but cross-chain messages from Monad may be trusted by other chains

**Validation:**
- [ ] Verify proxy admin address on-chain
- [ ] Confirm no timelock on Monad factory proxy admin

---

### C2. CREATE2 Address Overlap — Arbitrum, Monad, Katana

| Field | Value |
|---|---|
| **ID** | `AE-C-002` |
| **Category** | Address Predictability |
| **Contracts** | `AmplePerspective`, `AmpleEarnFactory` |
| **Chains** | Arbitrum, Monad, Katana (same salt) |
| **Status** | ✅ **Verified** |
| **Confidence** | **HIGH** |
| **Severity** | 🟢 **Low** |

**Finding:**
Arbitrum, Monad, and Katana use the same CREATE2 salt, resulting in identical addresses across 3 chains. Base uses a different salt. Factory address `0x9881...` is same on 3 chains.

---

### C3. Linked Library Addresses Identical Across All Chains

| Field | Value |
|---|---|
| **ID** | `AE-C-003` |
| **Category** | Library Consistency |
| **Contracts** | All scope contracts |
| **Chains** | All (identical addresses) |
| **Status** | ✅ **Verified** |
| **Confidence** | **HIGH** |
| **Severity** | 🟢 **Low** (informational) |

**Finding:**
| Library | Address |
|---|---|
| `AmplePayoutLib` | `0xaae4a8...` |
| `CuratorLib` | `0xaf5ad8...` |
| `ReallocateLib` | `0x9dc5c4...` |
| `StrategyLib` | `0x8ac4a2...` |

Identical across Base, Arbitrum, Monad, and Katana. If any library has a vulnerability, it affects ALL chains.

---

### C4. LayerZero Peer Configuration — Centralized Control

| Field | Value |
|---|---|
| **ID** | `AE-C-004` |
| **Category** | Cross-Chain Trust |
| **Contracts** | `AmpleEarnCrossChainRouter` |
| **Chains** | All |
| **Status** | ✅ **Verified** |
| **Confidence** | **HIGH** |
| **Severity** | 🟡 **High** (requires owner compromise) |

**Finding:**
`setPeer(eid, peerAddress)` is onlyOwner. Owner can redirect cross-chain messages to any destination.

**Validation:**
- [ ] Check current peer configurations on each chain via on-chain data
- [ ] Confirm multi-sig threshold and signers

---

## D. PRIVILEGED FUNCTION RISKS

### D1. `setPerspective()` — Strategy Validation Backdoor

| Field | Value |
|---|---|
| **ID** | `AE-P-001` |
| **Category** | Privileged Access |
| **Contracts** | `AmpleEarnFactory` |
| **Chains** | All |
| **Status** | ✅ **Verified** |
| **Confidence** | **HIGH** |
| **Severity** | 🔴 **Critical** (requires owner compromise) |

**Path:** Owner → `setPerspective(malicious)` → malicious `isVerified()` returns true for any vault → deposits to fake strategy.

---

### D2. `setPeer()` — Cross-Chain Message Hijack

| Field | Value |
|---|---|
| **ID** | `AE-P-002` |
| **Category** | Privileged Access |
| **Contracts** | `AmpleEarnCrossChainRouter` |
| **Chains** | All |
| **Status** | ✅ **Verified** |
| **Confidence** | **HIGH** |
| **Severity** | 🟡 **High** (requires owner compromise) |

**Path:** Owner → `setPeer(dstEid, attackerEndpoint)` → all claims to that destination go to attacker.

---

### D3. Proxy Upgrade (Monad)

| Field | Value |
|---|---|
| **ID** | `AE-P-003` |
| **Category** | Privileged Access |
| **Contracts** | `AmpleEarnFactory` (Monad proxy) |
| **Chain** | Monad |
| **Status** | ✅ **Verified** |
| **Confidence** | **HIGH** |
| **Severity** | 🔴 **Critical** (requires owner compromise) |

**Path:** Owner → `upgradeTo(maliciousImpl)` → factory logic replaced → all future vaults compromised.

---

### D4. Curator — Timelocked Cap Bypass

| Field | Value |
|---|---|
| **ID** | `AE-P-004` |
| **Category** | Privileged Access |
| **Contracts** | `EulerEarn` (via `CuratorLib`) |
| **Chains** | All |
| **Status** | ⚠️ **Needs Investigation** |
| **Confidence** | **LOW-MEDIUM** |
| **Severity** | 🟠 **Medium** |

**Path:** Curator submits cap → Guardian cancels → Curator re-submits in same block after cancellation.

**Validation Required:**
- [ ] Test: can curator immediately re-submit after guardian cancel?

---

## E. OUT-OF-SCOPE / DEPENDENCY FINDINGS

### E1. Euler EVK Oracle Manipulation Propagation

| Field | Value |
|---|---|
| **ID** | `AE-O-001` |
| **Category** | Oracle Manipulation |
| **Contracts** | Euler EVK strategies (out of scope) |
| **Chains** | All |
| **Status** | ❓ **Unknown** |
| **Confidence** | **LOW** |
| **Severity** | 🟡 **High** (if feasible) |

**Path:** Chainlink manipulation → EVK strategy totalAssets() → AmpleEarn share price → attacker deposits/withdraws at wrong rate.

---

### E2. Flashloan + EVK Strategy Share Manipulation

| Field | Value |
|---|---|
| **ID** | `AE-O-002` |
| **Category** | Flashloan Attack |
| **Contracts** | Euler EVK strategies (out of scope) |
| **Chains** | All |
| **Status** | ❓ **Unknown** |
| **Confidence** | **LOW** |
| **Severity** | 🟠 **Medium** |

**Path:** Flashloan USDC → deposit into EVK strategy → share price inflated → deposit/withdraw AmpleEarn at wrong rate.

---

### E3. LayerZero Validator Compromise

| Field | Value |
|---|---|
| **ID** | `AE-O-003` |
| **Category** | Cross-Chain Security |
| **Contracts** | LayerZero DVN (out of scope) |
| **Chains** | All |
| **Status** | ❓ **Unknown** |
| **Confidence** | **LOW** |
| **Severity** | 🔴 **Critical** |

**Note:** Requires compromise of LayerZero infrastructure — outside audit scope.

---

## F. EDGE CASES

| ID | Description | Impact | Likelihood |
|---|---|---|---|
| `AE-E-001` | Fee-on-transfer USDC — `_deposit()` over-accounts | Share inflation | Extremely low |
| `AE-E-002` | `withdraw()` transfers exact amount but vault has less after fee | Revert | Extremely low |
| `AE-E-003` | `deposit(0)` — mints 0 shares | Waste of gas | Medium |
| `AE-E-004` | `withdraw(0, addr, addr)` — rebalance but no transfer | State manipulation | Low |
| `AE-E-005` | `deposit(type(uint256).max)` — overflow in share calc | DoS | Low (0.8.x safe) |
| `AE-E-006` | Same `payoutId` on 2 chains simultaneously | Double payout | Low-Medium |
| `AE-E-007` | EVK bad debt → `lastTotalAssets` decreases → late withdrawers lose | Unfair loss | Medium |
| `AE-E-008` | Cross-chain claim with insufficient destination gas | Failed payout | Low |

---

## G. INVESTIGATION PRIORITIES

### Priority Matrix

| Priority | Finding | Title | Impact | Confidence | Recommended Action |
|---|---|---|---|---|---|
| **🔴 P0** | `AE-F-002` | Cross-Chain Payout Replay | 🟡 High | MEDIUM | Fork test payoutId uniqueness |
| **🔴 P0** | `AE-F-001` | ERC-4626 Donation Attack | 🟡 High | MEDIUM | Fork test share inflation |
| **🟡 P1** | `AE-F-003` | msg.value Loop Overpayment | 🟠 Medium | HIGH | Verify refund logic |
| **🟡 P1** | `AE-F-005` | nonReentrant Missing | 🟠 Medium | MEDIUM | Test contract reentrancy |
| **🟡 P1** | `AE-F-004` | Uninitialized totalValueUsed | 🟠 Medium | HIGH | Confirm safe by 0.8.x |
| **🟡 P2** | `AE-P-004` | Curator Cap Bypass | 🟠 Medium | LOW | Simulate cancel + re-submit |
| **🟡 P2** | `AE-C-001` | Monad Factory Proxy | 🟠 Medium | HIGH | Verify proxy admin |
| **🟢 P2** | `AE-O-001` | Oracle Manipulation | 🟡 High | LOW | Check EVK strategy config |

### Suggested Fork Tests (in order)

```
1. [Base] ERC-4626 Donation — transfer 1000 USDC to vault, deposit 1 USDC, check shares
2. [Arbitrum] Cross-Chain Replay — claim payoutId on Base, attempt same on Arbitrum
3. [Base] batchCrossChainClaimPayout — test with attacker contract reentrancy
4. [Base] msg.value underpayment — send insufficient gas for multi-destination batch
5. [Monad] Factory proxy — verify implementation address on-chain
6. [Arbitrum] Curator cap bypass — submit, cancel, re-submit in one block
```

---

## H. CHECKLIST STATUS SUMMARY

| Category | Total | ✅ Verified | ⚠️ Needs Investigation | ❓ Unknown |
|---|---|---|---|---|
| **A. In-Scope Vulnerabilities** | 6 | 4 | 2 | 0 |
| **B. Static Analysis (scope only)** | 21 | 21 | 0 | 0 |
| **C. Config / Deployment** | 4 | 4 | 0 | 0 |
| **D. Privileged Functions** | 4 | 3 | 1 | 0 |
| **E. Out-of-Scope / Dependencies** | 3 | 0 | 0 | 3 |
| **F. Edge Cases** | 8 | 0 | 8 | 0 |
| **Total** | **46** | **32** | **11** | **3** |

---

## I. NEXT STEPS

| Step | Action | Target |
|---|---|---|
| 1 | Fork test: ERC-4626 Donation Attack (Base) | P0 |
| 2 | Fork test: Cross-Chain Payout Replay (Arbitrum) | P0 |
| 3 | Fork test: batchCrossChainClaimPayout reentrancy | P1 |
| 4 | On-chain verify Monad proxy admin | P2 |
| 5 | On-chain verify LayerZero peer config | P2 |
| 6 | Update findings with PoC results | Ongoing |

---

*Document generated from: RECON_PER_CHAIN.md, CROSS_CHAIN_COMPARISON.md, Slither reports, ATTACK_SURFACES.md, HYPOTHESES.md, FINDINGS.md, THREAT_MODEL.md, PRIVILEGED_FUNCTIONS.md, EDGE_CASES.md*
