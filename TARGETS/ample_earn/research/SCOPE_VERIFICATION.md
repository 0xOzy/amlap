# Scope Verification for AmpleProof Findings

## Relevant Scope Excerpts

From `TARGETS/ample_earn/metadata/SCOPE.md`:

### In-Scope Contracts (per chain)

| Chain | AmplePerspective | AmpleEarnFactory | AmpleEarnCrossChainRouter |
|-------|-----------------|-----------------|--------------------------|
| Monad | `0x4b8057e5...` | `0x9881464a...` | `0xc9086278...` |
| Base  | `0x801ad316...` | `0x62b30451...` | `0xf132654d...` |
| Arbitrum | `0x4b8057e5...` | `0x9881464a...` | `0xcab6a410...` |
| Katana | `0x4b8057e5...` | `0x9881464a...` | `0x7beb2204...` |

### Out-of-Scope
- Theoretical without PoC
- Old compiler / non-locked compiler
- Vulnerabilities in imported contracts (OpenZeppelin, Solmate, LayerZero)
- Code style / gas optimizations
- Front-run only attacks

### Known Issues
- All Pashov Audit Group findings (2 audits)
- Euler Earn acknowledged issues
- Third-party Euler vault risk

---

## Finding Scope Cross-Reference

| Finding ID | Affected Contract | Contract Type | In Scope? | Notes |
|-----------|------------------|---------------|-----------|-------|
| **AE-F-002** | `AmpleEarn.sol` (vault) | Vault implementation | ✅ **In scope** | Vaults are deployed by the in-scope `AmpleEarnFactory`. The `payoutPool` mapping (line 65) is part of the protocol's core contract system. |
| **AE-F-005** | `AmpleEarnCrossChainRouter.sol` | Router | ✅ **In scope** | Explicitly listed as in-scope on all 4 chains. The `batchCrossChainClaimPayout` function (line 89) is directly within the scope boundary. |
| **AE-F-007** | `AmpleEarn.sol` + `AmpleEarnCrossChainRouter.sol` | Combined (Vault + Router) | ✅ **In scope** | Both contracts are in scope (see above). The combined finding is a logical composition of two in-scope vulnerabilities. |

### Detailed Analysis

#### AE-F-002: Cross-Chain Payout Replay
- **Primary contract**: `AmpleEarn.sol` — the vault implementation deployed by `AmpleEarnFactory`.
- **Scope consideration**: The vault contract (`AmpleEarn.sol`) is not explicitly listed by address in the scope, but it is the core protocol contract deployed by the in-scope `AmpleEarnFactory`. In standard bug bounty practice, contracts deployed by in-scope factories are considered part of the protocol and are in scope. The scope lists `AmpleEarnFactory` which deploys and manages vaults.
- **Out-of-scope check**: Cross-chain replay is not listed as a known issue or out-of-scope item. It is not a theoretical vulnerability (confirmed via fork test). It is not a compiler issue, imported contract vulnerability, gas optimization, or front-run attack.
- **Verdict**: ✅ **In scope**

#### AE-F-005: Missing nonReentrant in batchCrossChainClaimPayout
- **Primary contract**: `AmpleEarnCrossChainRouter.sol` — explicitly listed as in-scope on all chains.
- **Out-of-scope check**: Reentrancy is not listed as a known issue or out-of-scope item. The PoC is not theoretical (confirmed via unit test). Not a compiler/import/gas/front-run issue.
- **Verdict**: ✅ **In scope**

#### AE-F-007: Combined Amplification (AE-F-002 + AE-F-005)
- **Contracts involved**: Both `AmpleEarn.sol` (vault) and `AmpleEarnCrossChainRouter.sol` (router) — both in scope.
- **Verdict**: ✅ **In scope**

---

## Exclusion Risk Assessment

| Exclusion Criteria | AE-F-002 | AE-F-005 | AE-F-007 |
|-------------------|----------|----------|----------|
| Theoretical without PoC | ❌ Not excluded — fork test exists | ❌ Not excluded — unit test exists | ❌ Not excluded — both PoCs exist |
| Old compiler / non-locked compiler | ❌ Not applicable | ❌ Not applicable | ❌ Not applicable |
| Vulnerabilities in imported contracts | ❌ Not applicable — vulnerability is in protocol code | ❌ Not applicable — vulnerability is in protocol code | ❌ Not applicable |
| Code style / gas optimizations | ❌ Not applicable — this is an accounting invariant failure | ❌ Not applicable — this is a security control gap | ❌ Not applicable |
| Front-run only attacks | ❌ Not applicable — no front-running required | ❌ Not applicable — no front-running required | ❌ Not applicable |
| Known issues (Pashov/Euler) | ❌ Not listed as known issue | ❌ Not listed as known issue | ❌ Not listed as known issue |

---

## Conclusion

**All three findings (AE-F-002, AE-F-005, AE-F-007) are in scope.**

- `AmpleEarnCrossChainRouter.sol` is explicitly listed as in-scope on all chains.
- `AmpleEarn.sol` (the vault) is deployed by the in-scope `AmpleEarnFactory` and is a core protocol contract — standard bug bounty practice includes factory-deployed contracts.
- None of the out-of-scope exclusions apply to any finding.
- Cross-chain replay and reentrancy are not listed as known issues or acknowledged risks.
- All findings have working PoCs (fork test and/or unit test), satisfying the "not theoretical" requirement.

**Risk of scope rejection**: LOW
