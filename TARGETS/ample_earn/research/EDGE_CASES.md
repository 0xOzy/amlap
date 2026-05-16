# Edge Cases — Ample Earn

- Donate before first deposit (ERC-4626 inflation)
- Withdraw during active prize distribution
- Prize claim during LayerZero downtime
- Strategy cap increase + immediate removal
- Fee-on-transfer USDC (if USDC ever enables this)
- 0-value deposits / withdrawals
- Max uint256 deposit → overflow in share calculation
- Same payoutId claimed on 2 chains simultaneously
- Guardian cancels timelock, curator re-submits in same block
- Performance fee > yield accrued (negative yield period)
- Euler EVK bad debt → Earn vault "lostAssets" increase
- Cross-chain claim with insufficient gas on destination
