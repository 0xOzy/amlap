# False Positives & Invalidated Hypotheses

## AE-F-001 ERC-4626 Donation (Share Inflation)
- **Status**: Invalidated
- **Reason**: `VIRTUAL_AMOUNT = 1e6` effectively prevents classic donation attacks. No rounding or preview mismatch found.
- **Burden of proof**: Attacker would need to find a separate edge (e.g., rebasing interaction) — none identified.

## AE-F-006 Redundant Parameter
- **Status**: Not a vulnerability
- **Reason**: Extra function parameter does not affect logic or security. Could be removed for code quality, but no exploit.

## AE-C-001 Monad Proxy Upgrade (Admin Risk)
- **Status**: Informational (out of scope for HackenProof unless specifically included)
- **Reason**: Owner can upgrade proxy; this is a design choice, not a vulnerability unless owner is malicious. Covered by trust assumptions.

## Other Hypotheses (from agent's initial sweep)
- **`batchCrossChainClaimPayout` reentrancy**: Confirmed as griefing only, no fund drain.
- **`msg.value` loop overflow**: Solidified as low severity after analysis.

## Conclusion
Only **AE-F-002 Cross-Chain Payout Replay** remains as a valid, exploitable, and economically feasible finding. All others are either mitigated, informational, or non-exploitable.
