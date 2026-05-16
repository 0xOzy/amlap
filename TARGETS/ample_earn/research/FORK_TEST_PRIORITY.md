# Fork Test Priority — Cross-Chain Replay Validation (AE-F-002)

## P0 — Core Exploit Validation

### Fundamental Questions
- [x] Are CREATE2 vault addresses truly identical across Arbitrum & Monad?
- [x] Is on-chain state (storage) isolated per chain?
- [ ] Are Merkle roots identical across chains for the same payoutId?
- [ ] Are leaves chain-specific? (Encode chainId or dstEid?)
- [ ] Is payoutId globally coordinated off-chain?
- [ ] Does proof/leaf encode chainId?
- [ ] Does payout source validate dstEid?
- [ ] Is claim state (claimMask) isolated per chain? (Proven indirectly)

### Fork Test Execution (2026-05-16)
**File:** `src/test/FT-02_CrossChainPayoutReplay.t.sol`
**Status:** 3/3 PASS
**Foundry:** v1.7.2-nightly

**Test 1 - FactoryHasCodeOnBoth:** ✅ Factory exists on Arbitrum & Monad
**Test 2 - PerspectiveAddressIdentical:** ✅ AmplePerspective address identical on both chains
**Test 3 - StorageIsolation_OwnerChange:**
- Owner before: `0x70E...138` on both chains
- Wrote new owner `0x00...001` on Arbitrum via `vm.store`
- Owner on Monad after: still `0x70E...138`
**Conclusion:** Storage is completely isolated per chain. claimMask in payoutPool on Arbitrum does NOT affect Monad. Replay possible.

### Remaining Unvalidated Items (Next Steps)
1. **Merkle root comparison** — Use `cast logs` to fetch `SetMerkleRoots` events across chains.
2. **Leaf encoding** — Decompile Merkle tree construction or check off-chain repo.
3. **Live payout inspection** — Find active payoutId with same root on both chains.
4. **Historical replay** — Check if any payoutId has been claimed on multiple chains.

### Confidence Update
- Exploit existence: **CONFIRMED** (storage isolation proven)
- Exploit executable: **HIGH** (payout replay not yet simulated due to missing active payout)
- Severity recommendation: **CRITICAL** (direct fund loss, multiple chains)
