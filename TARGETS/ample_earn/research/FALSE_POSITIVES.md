# False Positives & Invalidated Hypotheses

## AE-F-001 ERC-4626 Donation (Share Inflation)
- Status: Invalidated
- Reason: VIRTUAL_AMOUNT = 1e6 effectively prevents classic donation attacks. No rounding or preview mismatch found.

## AE-F-006 Redundant Parameter
- Status: Not a vulnerability
- Reason: Extra function parameter does not affect logic or security.

## AE-C-001 Monad Proxy Upgrade (Admin Risk)
- Status: Informational (out of scope for HackenProof unless specifically included)
- Reason: Owner can upgrade proxy; this is a design choice, not a vulnerability.

## Other Hypotheses
All other flagged items during initial analysis have been reviewed and either mitigated, informational, or non-exploitable.

## Conclusion
Only AE-F-002 Cross-Chain Payout Replay and AE-F-005 Reentrancy Gap remain as valid, exploitable findings. All others are invalidated.
