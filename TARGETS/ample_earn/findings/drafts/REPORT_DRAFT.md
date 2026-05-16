# Ample Earn — Security Research Draft Report

**Target:** Prize-linked savings protocol on Euler Earn (HackenProof bounty, up to $20K Critical)
**Scope:** AmplePerspective, AmpleEarnFactory, AmpleEarnCrossChainRouter — 12 contracts (3 types × 4 chains)
**Date:** 2026-05-15
**Researcher:** AI Security Research Framework
**Status:** DRAFT — Awaiting fork test validation

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Research Scope & Methodology](#research-scope--methodology)
3. [Protocol Overview](#protocol-overview)
4. [Finding Summaries](#finding-summaries)
5. [Per-Node Checklist](#per-node-checklist)
6. [Fork Test Plan](#fork-test-plan)
7. [Next Steps](#next-steps)
8. [References](#references)

---

## Executive Summary

### Overall Risk Assessment

| Severity | Count | Key Finding |
|---|---|---|
| **🔴 Critical** | 1 | AE-F-002: Cross-Chain Payout Replay — double-claim prize across multiple chains |
| **🟡 High** | 2 | AE-P-001: Privileged function risks (setPerspective, LayerZero peer config) |
| **🟠 Medium** | 4 | AE-F-005: Reentrancy gap, AE-F-003: msg.value loop, AE-C-001: Monad proxy, AE-P-004: Curator bypass |
| **🟢 Low / Info** | 39 | Static analysis (21), edge cases (8), config (4), other (6) |
| **Total** | **46** | 32 verified, 11 need investigation, 3 out-of-scope |

### Most Critical Finding

**AE-F-002: Cross-Chain Payout Replay (VERIFIED via Source Analysis)**

- **Impact:** Attacker can claim the same prize `payoutId` on multiple EVM chains (Arbitrum, Monad, Katana) because `payoutPool[payoutId]` is a per-chain mapping with no cross-chain guard (`AmpleEarn.sol:65`).
- **Profit potential:** $15–$5,300 per exploit cycle; ROI 10,000%+
- **Exploitability:** MEDIUM-HIGH — only requires monitoring payout cycles and submitting 2-3 transactions
- **Chain impact:** Arbitrum, Monad, Katana share CREATE2 salt → identical vault addresses → vulnerable
- **Base:** Shielded by unique CREATE2 salt (different vault addresses)

---

## Research Scope & Methodology

### Chains Analyzed

| Chain | TVL | Scope Contracts | Key Difference |
|---|---|---|---|
| **Base (OP Stack)** | $4.33M | Perspective, Factory, Router | Immutable; unique CREATE2 salt |
| **Arbitrum (Nitro)** | $118K | Perspective, Factory, Router | Immutable; shared CREATE2 salt |
| **Monad** | $4.7K | Perspective, Factory (**PROXY**), Router | **Factory is proxy**; shared CREATE2 salt |
| **Katana** | $5.7K | Perspective, Factory, Router | Immutable; shared CREATE2 salt |

### Methodology

1. **Recon & Source Extraction** — 12 Solidity contracts extracted from Sourcify JSON metadata across 4 chains
2. **Cross-Chain Bytecode Comparison** — MD5 checksums, source diff, deployment pattern analysis
3. **Static Analysis** — Slither (231 findings, 21 scope-specific), Semgrep (parser-limited for 0.8.26)
4. **Invariant Modeling** — 14 accounting invariants + 7 prize invariants + 4 cross-chain invariants
5. **Threat Modeling** — 7 threats across 6 attacker profiles with full exploit sequences
6. **Exploit Synthesis** — 4 exploit chains from combined attack primitives (flashloan, bridge, oracle, governance, ERC-4626, reward accounting patterns)
7. **Profitability Analysis** — ROI, gas costs, capital requirements, expected value per hypothesis

### Documents Generated

| Document | Lines | Content |
|---|---|---|
| `research/RESEARCH_LENGKAP.md` | 959 | Kompilasi lengkap seluruh analisis |
| `research/RECON_PER_CHAIN.md` | 245 | Per-chain proxy, oracle, flashloan analysis |
| `research/CROSS_CHAIN_COMPARISON.md` | 420 | Bytecode diff, deployment differences |
| `research/ACCOUNTING_INVARIANTS.md` | 741 | 14 invariants per invariant_template.md |
| `research/THREAT_LIST.md` | 612 | 7 threats per threat_template.md |
| `research/EXPLOIT_SYNTHESIS.md` | 482 | 4 exploit chains |
| `research/EXPLOIT_STEPS.md` | 1,380 | 3 hypotheses + fork test scripts |
| `research/HYPOTHESES.md` | 446 | 3 hypotheses with pattern combinations |
| `research/FINDINGS_CHECKLIST.md` | 500 | 46 findings checklist |
| `findings/drafts/AE-F-002_CrossChainPayoutReplay.md` | 656 | Full CRITICAL finding report |
| `findings/drafts/AE-F-005_ReentrancyGap.md` | 82 | MEDIUM: reentrancy gap |
| `findings/drafts/AE-C-001_MonadProxy.md` | 47 | MEDIUM: Monad proxy risk |

### Tools Used

- **Slither** — Static analysis (4 chain reports: 9,601 lines)
- **Semgrep** — Pattern detection (parser-limited for Solidity 0.8.26)
- **Foundry** — Compilation verification, fork test framework
- Manual source code review (Solidity 0.8.26, LayerZero OApp v2)

---

## Protocol Overview

### Architecture

```
User → deposit(USDC) → AmpleEarn vault (ERC-4626)
  → Euler Earn meta-vault → EVK strategies → yield
                                                ↓
                                           Prize pool
                                                ↓
User ← CrossChainRouter ← LayerZero ←  Winner selection (VRF)
```

### Layer Architecture

```
Lapisan 1: Ample Earn (Prize Logic)
  ├─ AmpleEarn — ERC-4626 vault + prize distribution
  │   ├─ PayoutPool: merkle root-based prize claims
  │   ├─ VRF: verifiable randomness for winner selection
  │   └─ AmpleEarnReserve: escrow for payout
  ├─ AmpleEarnFactory — CREATE2 factory
  └─ AmpleEarnCrossChainRouter — LayerZero OApp

Lapisan 2: Euler Earn (Yield Logic)
  ├─ ERC-4626 meta-vault per asset
  ├─ Supply queue & withdraw queue (max 30 strategies)
  ├─ Performance fee (up to 100%)
  └─ Timelocked risk actions

Lapisan 3: Euler EVK (Lending)
  └─ Lending vaults, collateral, oracles (Chainlink)
```

### Key Contracts

| Contract | Lines | Role |
|---|---|---|
| **AmplePerspective** | 94 | Strategy verification (EnumerableSet membership) |
| **AmpleEarnFactory** | 153 | CREATE2 vault deployment + perspective management |
| **AmpleEarnCrossChainRouter** | 167 | LayerZero OApp for cross-chain prize claims |
| **AmpleEarn** (underlying) | 290 | ERC-4626 vault + prize distribution + payout reserve |
| **EulerEarn** (underlying) | 1,023 | Strategy allocation + yield accrual + fee management |
| **AmplePayoutLib** | 130 | Merkle proof verification + claim mask logic |

### Privilege Model

```
Owner (multi-sig)
  ├── setPerspective(address)         → Strategy validation
  ├── setPeer(uint32, bytes32)        → Cross-chain routing
  ├── transferOwnership               → Owner transfer
  ├── setIsPayoutManager(address,bool)→ Prize distribution
  └── upgradeTo(address)              → [Monad only] Factory upgrade

Curator     → submitCap(), submitMarketRemoval() (timelocked)
Guardian    → revokePendingTimelock(), cancelTimelock()
Allocator   → setSupplyQueue(), updateWithdrawQueue(), reallocate()
PayoutManager → setMerkleRoots()
```

### Trust Boundaries

| Trust Level | Actors | Risk |
|---|---|---|
| **TRUSTED** | Owner (multi-sig), Curator, Guardian | Can drain all funds if compromised |
| **SEMI-TRUSTED** | PayoutManager, Allocator | Limited to prize distribution + allocation |
| **UNTRUSTED** | Users, LayerZero DVN, EVK Strategies | No special permissions |

---

## Finding Summaries

### 🔴 Finding AE-F-002: Cross-Chain Payout Replay

| Field | Value |
|---|---|
| **Severity** | **🔴 CRITICAL** |
| **Confidence** | **MEDIUM-HIGH** (source confirmed, awaiting fork test) |
| **Contracts** | `AmpleEarn.sol` L65 — `payoutPool[payoutId]` mapping |
| **Root Cause** | Mapping keyed **only** by `payoutId` — no vault or chain identifier |
| **Chains** | Arbitrum, Monad, Katana (shared CREATE2 salt → same vault addresses) |
| **Profit per cycle** | $15–$5,300 |
| **ROI** | 10,000%+ |
| **Gas cost** | ~$0.20–$1.50 per 3-chain exploit |
| **Fork test** | `src/test/FT-02_CrossChainPayoutReplay.t.sol` |

**Attack Scenario:**
1. Monitor Arbitrum for `SetMerkleRoots` events → capture `payoutId`, `leaf`, `proof`
2. Check if same vault address exists on Monad/Katana (CREATE2 = same address)
3. Submit `claimPayout(payoutId, leaf, proof)` on Arbitrum → legitimate claim ✅
4. Submit **same** `claimPayout(payoutId, leaf, proof)` on Monad → independent storage → claim succeeds again ✅
5. Repeat for Katana → triple payout ✅

Full details: [`findings/drafts/AE-F-002_CrossChainPayoutReplay.md`](AE-F-002_CrossChainPayoutReplay.md)

---

### 🟠 Finding AE-F-005: batchCrossChainClaimPayout Missing nonReentrant

| Field | Value |
|---|---|
| **Severity** | **🟠 MEDIUM** |
| **Confidence** | **MEDIUM** |
| **Contracts** | `AmpleEarnCrossChainRouter.sol` L89-133 |
| **Chains** | All |
| **Issue** | `batchCrossChainClaimPayout()` performs external call to LayerZero and refund `.call{value}` to `msg.sender` **without** `nonReentrant` protection. The refund call at L130 is a reentrancy vector if `msg.sender` is a contract. |
| **Mitigation** | Add `nonReentrant` modifier from OpenZeppelin's `ReentrancyGuard` |

Full details: [`findings/drafts/AE-F-005_ReentrancyGap.md`](AE-F-005_ReentrancyGap.md)

---

### 🟠 Finding AE-F-003: msg.value Loop Overpayment

| Field | Value |
|---|---|
| **Severity** | **🟠 MEDIUM** |
| **Confidence** | **HIGH** |
| **Contracts** | `AmpleEarnCrossChainRouter.sol` L89-133 |
| **Chains** | All |
| **Issue** | `msg.value` used in loop; refund only at end. If one destination fails mid-batch, partial LZ messages sent before revert. Overpayment not refunded per iteration. |

---

### 🟠 Finding AE-F-004: Uninitialized Local Variables

| Field | Value |
|---|---|
| **Severity** | **🟠 MEDIUM** |
| **Confidence** | **HIGH** (mitigated by Solidity 0.8.x defaults to 0) |
| **Contracts** | `CrossChainRouter` (L98), `EulerEarn` (L759), `ReallocateLib` (L43-57) |
| **Chains** | All |
| **Issue** | Variables like `totalValueUsed` not explicitly initialized. Solidity 0.8.26 defaults to 0, but code quality concern. |

---

### 🟠 Finding AE-C-001: Monad Factory Proxy

| Field | Value |
|---|---|
| **Severity** | **🟠 MEDIUM** |
| **Confidence** | **HIGH** |
| **Contracts** | `AmpleEarnFactory` on Monad only |
| **Chains** | Monad |
| **Issue** | Factory behind OpenZeppelin Transparent Proxy — no timelock on upgrade. Owner can replace logic at any time. |
| **Impact** | TVL Monad only $4.7K; cross-chain escalation blocked by LayerZero DVN |

Full details: [`findings/drafts/AE-C-001_MonadProxy.md`](AE-C-001_MonadProxy.md)

---

### 🟡 Finding AE-P-001: setPerspective — Strategy Validation Backdoor

| Field | Value |
|---|---|
| **Severity** | **🟡 HIGH** (requires owner compromise) |
| **Confidence** | **HIGH** |
| **Contracts** | `AmpleEarnFactory` |
| **Chains** | All |
| **Path** | Owner → `setPerspective(maliciousContract)` → `maliciousContract.isVerified()` returns true for any strategy → vault deployments bypass strategy validation → funds sent to attacker-controlled addresses |

---

### 🟡 Finding AE-P-002: setPeer — Cross-Chain Message Hijack

| Field | Value |
|---|---|
| **Severity** | **🟡 HIGH** (requires owner compromise) |
| **Confidence** | **HIGH** |
| **Contracts** | `AmpleEarnCrossChainRouter` |
| **Chains** | All |
| **Path** | Owner → `setPeer(dstChainId, attackerEndpoint)` → all cross-chain claims to that destination chain redirected to attacker-controlled endpoint |

---

### 🟢 Static Analysis Findings (AE-S-001 through AE-S-021)

21 scope-specific findings from Slither analysis. See full table in `FINDINGS_CHECKLIST.md`.

Key items:

| ID | Detector | Impact | Contract | Description |
|---|---|---|---|---|
| AE-S-001 | `arbitrary-send-erc20` | HIGH | SafeERC20Permit2Lib | Arbitrary `from` in transferFrom with permit2 |
| AE-S-002 | `msg-value-loop` | HIGH | CrossChainRouter | msg.value used in batch loop |
| AE-S-010 | `unused-return` | MEDIUM | SafeERC20Permit2Lib | Permit2 return value ignored |
| AE-S-012 | `shadowing-local` | LOW | EulerEarn | `owner` shadows Ownable |
| AE-S-016 | `low-level-calls` | INFO | CrossChainRouter | `.call{value}` to msg.sender |
| AE-S-020 | `redundant-statement` | INFO | CrossChainRouter | Unused LZ params (_guid, _executor, _extraData) |

### 🟢 Edge Cases (AE-E-001 through AE-E-008)

| ID | Description | Impact | Likelihood |
|---|---|---|---|
| AE-E-001 | USDC fee-on-transfer — `_deposit()` over-accounts assets | Share inflation | Extremely low |
| AE-E-006 | **Same payoutId on 2 chains simultaneously** | **Double payout** | **LOW-MEDIUM** |
| AE-E-007 | EVK bad debt → `lastTotalAssets` decreases → late withdrawers lose | Unfair loss | MEDIUM |
| AE-E-008 | Cross-chain claim with insufficient destination gas | Failed payout | LOW |

---

## Per-Node Checklist Status

### Completed (32 items)

| Category | Count | Status |
|---|---|---|
| In-Scope Vulnerabilities | 4 | ✅ Verified via source code |
| Static Analysis (scope only) | 21 | ✅ Slither reports complete (4 chains) |
| Config / Deployment | 4 | ✅ Verified via metadata |
| Privileged Functions | 3 | ✅ Verified via source code |

### Pending Investigation (11 items)

| ID | Title | Priority | Action Needed |
|---|---|---|---|
| AE-F-001 | ERC-4626 Donation Attack | P0 | Fork test (Base) |
| **AE-F-002** | **Cross-Chain Payout Replay** | **P0** | **Fork test (Arb + Monad + Katana)** |
| AE-P-004 | Curator Timelocked Cap Bypass | P2 | Simulation |
| AE-C-001 | Monad Proxy Admin | P2 | On-chain verification |
| AE-C-004 | LayerZero Peer Config | P2 | On-chain verification |
| AE-E-001 through AE-E-008 | Edge Cases | P3 | Scenario simulation |

### Unknown / Out-of-Scope (3 items)

| ID | Title | Reason |
|---|---|---|
| AE-O-001 | Oracle Manipulation Propagation | Requires EVK strategy analysis (out of scope) |
| AE-O-002 | Flashloan + Share Manipulation | Requires EVK strategy analysis (out of scope) |
| AE-O-003 | LayerZero Validator Compromise | Requires LayerZero infrastructure analysis (out of scope) |

---

## Fork Test Plan

### Primary: AE-F-002 Cross-Chain Payout Replay

| File | `src/test/FT-02_CrossChainPayoutReplay.t.sol` |
|---|---|
| **Chains** | Arbitrum + Monad + Katana |
| **Requires** | RPC URLs for all 3 chains in env vars |
| **Tests** | 5 test functions |
| **Core assertion** | `isPayoutClaimed(payoutId)` returns `false` on chain B after being claimed on chain A |

#### Test Descriptions

| Test | Purpose |
|---|---|
| `test_FactoryAddressesMatch()` | Verify Factory `0x9881...` has code on all 3 chains |
| `test_PerspectiveMatches()` | Verify Perspective address identical across chains |
| `test_VaultExistsOnAllChains()` | Enumerate vaults; identify cross-chain replay targets |
| `test_PayoutIsolation_ExploitProof()` | **Core exploit proof**: verify payoutId claim state is independent per chain |
| `test_GasCostEstimation()` | Estimate gas costs and profitability |

#### How to Run

```bash
# Set RPC URLs
export ARBITRUM_RPC_URL="https://arb1.arbitrum.io/rpc"
export MONAD_RPC_URL="..."  # Replace with actual Monad RPC
export KATANA_RPC_URL="..." # Replace with actual Katana RPC

# Run fork test
forge test --match-test test_CrossChainPayoutReplay -vvv
```

### Secondary: Other Fork Tests

| Test | File | Priority |
|---|---|---|
| ERC-4626 Share Inflation | (to be created) | P1 |
| Router Reentrancy | (to be created) | P1 |
| Monad Proxy Upgrade | (to be created) | P2 |

---

## Next Steps

| Priority | Action | Target | Depends On |
|---|---|---|---|
| **🔴 P0** | Run fork test: Cross-Chain Payout Replay | Arb + Monad + Katana | RPC URLs for all 3 chains |
| **🟡 P1** | Create & run Router Reentrancy fork test | Base | RPC URL |
| **🟡 P1** | On-chain verify Monad proxy admin address | Monad | RPC URL |
| **🟡 P2** | On-chain verify LayerZero peer config per chain | All chains | RPC URLs |
| **🟢 P3** | Create & run ERC-4626 Donation fork test | Base | RPC URL + vault state |
| **🟢 P3** | Review Pashov audit reports (2 existing) | — | Access to reports |
| **🟢 P3** | Verify Curator cap bypass scenario | All chains | Simulation |

---

## References

| Document | Location | Lines |
|---|---|---|
| Research Lengkap | `research/RESEARCH_LENGKAP.md` | 959 |
| Recon Per Chain | `research/RECON_PER_CHAIN.md` | 245 |
| Cross-Chain Comparison | `research/CROSS_CHAIN_COMPARISON.md` | 420 |
| Accounting Invariants | `research/ACCOUNTING_INVARIANTS.md` | 741 |
| Threat List | `research/THREAT_LIST.md` | 612 |
| Findings Checklist | `research/FINDINGS_CHECKLIST.md` | 500 |
| Exploit Synthesis | `research/EXPLOIT_SYNTHESIS.md` | 482 |
| Exploit Steps | `research/EXPLOIT_STEPS.md` | 1,380 |
| Hypotheses | `research/HYPOTHESES.md` | 446 |
| Threat Model | `research/THREAT_MODEL.md` | 209 |
| Invariants | `research/INVARIANTS.md` | 264 |
| Privileged Functions | `research/PRIVILEGED_FUNCTIONS.md` | 25 |
| Edge Cases | `research/EDGE_CASES.md` | 14 |
| Call Graph | `research/CALL_GRAPH.md` | 26 |
| AE-F-002 (CRITICAL) | `findings/drafts/AE-F-002_CrossChainPayoutReplay.md` | 656 |
| AE-F-005 (Medium) | `findings/drafts/AE-F-005_ReentrancyGap.md` | 82 |
| AE-C-001 (Medium) | `findings/drafts/AE-C-001_MonadProxy.md` | 47 |
| Slither Base | `artifacts/slither_reports/slither_base.md` | 2,378 |
| Slither Arbitrum | `artifacts/slither_reports/slither_arbitrum.md` | 2,379 |
| Slither Monad | `artifacts/slither_reports/slither_monad.md` | 2,385 |
| Slither Katana | `artifacts/slither_reports/slither_katana.md` | 2,379 |
| Semgrep Reports | `artifacts/semgrep_reports/` | 80 |

---

*Draft generated from: RESEARCH_LENGKAP.md, FINDINGS_CHECKLIST.md, EXPLOIT_STEPS.md, THREAT_LIST.md, ACCOUNTING_INVARIANTS.md, RECON_PER_CHAIN.md, CROSS_CHAIN_COMPARISON.md, Slither reports, Semgrep reports*

**Next action required:** Run `FT-02_CrossChainPayoutReplay.t.sol` fork test to validate the **CRITICAL** finding AE-F-002.