# TODO Checklist — Ample Earn Research

## ✅ Completed (Tugas 1-3)
- [x] Slither static analysis — Base chain (231 findings, 110 in scope)
- [x] Slither static analysis — Arbitrum chain (231 findings)
- [x] Slither static analysis — Monad chain (231 findings + proxy note)
- [x] Slither static analysis — Katana chain (231 findings)
- [x] Semgrep analysis — all 4 chains (limited by parser)
- [x] Recon per chain — Proxy, Oracle, Rebasing, Delegatecall, Integrations, Flashloan
- [x] Cross-chain comparison — Source diff, deployment pattern, compiler config, linked libs
- [x] Attack surface identification (8 surfaces documented)
- [x] Privileged functions mapping (4 functions, 3 roles)
- [x] External calls mapping (complete call graph)
- [x] Proxy/upgrade pattern analysis
- [x] Oracle dependency analysis
- [x] FINDINGS_CHECKLIST.md — 46 items across 9 categories

## 🔴 P0 — Fork Test Required
- [ ] **Test ERC-4626 donation attack on fork** (Base) — AE-F-001
- [ ] **Verify cross-chain replay protection** (payoutId tracking) — AE-F-002

## 🟡 P1 — Investigation / Validation
- [ ] **Test batchCrossChainClaimPayout reentrancy** — AE-F-005
- [ ] **Verify msg.value refund logic** — AE-F-003
- [ ] **Verify uninitialized local variables** are safe (0.8.x defaults) — AE-F-004

## 🟡 P2 — Secondary Verification
- [ ] **Test strategy cap timelock bypass scenarios** — AE-P-004
- [ ] **Audit LayerZero peer configuration per chain** — AE-C-004
- [ ] **Verify Monad factory proxy admin** — AE-C-001
- [ ] **Cross-chain prize claim simulation** — AE-F-002 validation

## 🟢 P3 — Code Quality / Informational
- [ ] Review Pashov Audit Group findings (2 reports)
- [ ] Verify prize RNG mechanism
- [ ] Check Permit2 signature validation
- [ ] Review Euler Earn "realized losses" handling
- [ ] Compare AmpleEarn ERC-4626 against OpenZeppelin reference
- [ ] Map full call graph for AmplePerspective
