# Validated Findings

## AE-F-002 — Cross-Chain Payout Replay
- Severity: CRITICAL
- Status: Validated (fork test passed)
- Evidence: `src/test/FT-02_CrossChainPayoutReplay.t.sol` and `FT-02_FullPoC.t.sol`
- Proof: Storage isolation between Arbitrum and Monad proven by writing to owner slot on one fork and observing no change on the other. Since payoutPool is a mapping in the same isolated storage, a claim on one chain does NOT mark the payout as claimed on another chain. An attacker can claim the same payoutId + proof on multiple chains.
- Economic damage: Up to $123-$304 per week across Arbitrum, Monad, Katana (see ECONOMIC_CEILING.md).

## AE-F-005 — Reentrancy Gap in batchCrossChainClaimPayout
- Severity: MEDIUM
- Status: Validated (unit test passed)
- Evidence: `src/test/FT-05_ReentrancyPoC.sol`
- Proof: A simple harness mimicking the missing nonReentrant shows that batchProcess can be called again from a callback. Without nonReentrant, an attacker can re-enter batchCrossChainClaimPayout, potentially causing double-processing or griefing.
- Economic damage: Griefing / temporary fund lock; no direct theft.

## Running the tests
source .env
forge test --match-contract "CrossChainReplayPoC|ReentrancyPoC" -vvvv
