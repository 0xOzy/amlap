# State Machine Analysis — Ample Earn

## Payout Lifecycle
1. **Pending** – Payout created off-chain, Merkle root not yet set on-chain.
2. **Active** – `payoutPool[payoutId]` set with `merkleRoot`, `remainingPayoutAmount`, `reserve`.
3. **Claimable** – User submits valid Merkle proof → `claimMask` updated, payout transferred.
4. **Exhausted** – `remainingPayoutAmount = 0` or all eligible winners claimed.

## Claim Lifecycle (per chain)
- **Pre-Claim** – `isPayoutClaimed[payoutId] == false`, `claimMask` has bits for other winners.
- **Claim Execution** – `claimPayout()` verifies proof, updates `claimMask`, transfers funds.
- **Post-Claim** – `isPayoutClaimed[payoutId] == true`, `claimMask` reflects winner bit.
- **Cross-Chain Claim** – `AmpleEarnCrossChainRouter.claim()` → LayerZero message → destination `_lzReceive()` → `claimPayout()`.

## Cross-Chain Message Lifecycle (LayerZero)
1. **Send** – Source `OAppSender._lzSend()` emits packet.
2. **Validation** – DVN verifies packet, writes to `MessageLib`.
3. **Commit** – Executor commits the message.
4. **Receive** – Destination `OAppReceiver._lzReceive()` validates peer and payload.
5. **Retry/Stuck** – Failed messages stored in `storedPayload`, can be retried or cleared by owner/guardian.

## Failed Execution Lifecycle
- **Revert in `_lzReceive()`** → message stored as `storedPayload`.
- **Owner/Guardian retry** → `retryPayload()` re-enters `_lzReceive()`.
- **Owner/Guardian clear** → `clearPayload()` marks as executed without effect.

## Exploit-Relevant Transitions
- Cross-chain replay depends on the fact that `payoutPool` and `isPayoutClaimed` are **not** synchronized across chains.
- A failed cross-chain claim can be retried, potentially causing double-claim if off-chain coordinator does not track chain-specific state.
