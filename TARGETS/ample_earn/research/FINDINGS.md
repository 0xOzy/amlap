# Potential Findings

---

# [MEDIUM?] ERC-4626 Share Inflation via Donation

Status: Needs validation

Hypothesis:
AmplePerspective may be vulnerable to ERC-4626 donation attack where an attacker manipulates exchange rate by donating tokens directly to the vault before a deposit.

Requirements:
- Vault accepts direct token transfers (no `msg.sender` check)
- Exchange rate depends on `balanceOf(vault)` rather than internal accounting

Missing Information:
- Does AmplePerspective use internal accounting or raw balance?
- Is there a `totalAssets()` override?

Next Step: Fork simulation — donate USDC before deposit, check share mint amount.

---

# [MEDIUM?] Cross-Chain Prize Claim Replay

Status: Needs validation

Hypothesis:
AmpleEarnCrossChainRouter may not enforce strict payoutId uniqueness across chains, allowing a prize claim to be replayed on a different destination chain.

Requirements:
- payoutId not globally unique per chain
- LayerZero message can be delivered to multiple peers

Next Step: Trace `CrossChainClaimExecuted` event emission and verify payoutId tracking per chain.
