# Economic Ceiling Analysis

## AE-F-002 Cross-Chain Replay
- **Per-payout cap**: `remainingPayoutAmount` in `payoutPool` (varies per cycle).
- **Max extractable per payoutId**: `remainingPayoutAmount * (number_of_vulnerable_chains - 1)`.
- **Affected chains**: Arbitrum, Monad, Katana → 3 chains → up to 2 extra claims per payoutId.
- **Realistic weekly ceiling**: Based on current TVL and prize distribution, estimated **$123–$304** per week (from agent's earlier analysis).
- **Annualized ceiling**: ~$6,400–$15,800 (assuming constant prize pool sizes).
- **Attacker cost**: Only gas fees (~$0.15–$5 per claim across chains).
- **ROI**: Essentially infinite if exploit succeeds.

### AE-F-005 Reentrancy (Griefing)
- **Direct profit**: None for attacker.
- **Damage**: Temporary fund lock, gas griefing (victims lose gas without successful claim).
- **Ceiling**: Limited by gas cost to attacker; may deter genuine users.

### AE-F-003 msg.value Loop Overpayment
- **Potential loss**: Refund logic may overpay attacker if loop calculation flawed.
- **Ceiling**: Depends on batch size and fee amount; likely <$50 per batch.

### Overall Protocol Risk Ceiling
- **Cross-chain replay** is the only finding with direct, scalable fund loss.
- Other findings are either griefing or low-impact.
