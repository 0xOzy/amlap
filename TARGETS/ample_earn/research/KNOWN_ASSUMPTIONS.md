# Known Assumptions — Ample Earn

- Euler Earn vault accounting is correct and audited
- Chainlink price feeds remain live and accurate
- LayerZero validators are honest
- Owner multi-sig behaves honestly
- On-chain randomness is truly unpredictable
- Prize distribution is fair (no bias)
- USDC remains stable ($1 peg)
- Permit2 signatures are validated correctly
- EVC batch execution is atomic

## Potentially Weak Assumptions
- Euler Earn "realized losses" don't socialize → early withdrawers may escape loss, late withdrawers stuck
- Timelock can be bypassed if curator and owner collude
- Cross-chain payoutId uniqueness relies on off-chain coordination
