# Trust Assumptions Matrix

| Assumption | Trusted Party | Failure Impact | Current Mitigation | Weakness |
|---|---|---|---|---|
| LayerZero DVN honest | DVN (Decentralized Verifier Network) | Forged cross-chain message, unauthorized claim | Multisig DVN configuration, OApp peer whitelist | DVN collusion risk if not sufficiently decentralized |
| payoutId globally coordinated | Off-chain backend / coordinator | Replay attack across chains | None (on-chain uniqueness missing) | Single point of failure; coordinator bugs could allow duplicate payoutId |
| Merkle roots synchronized across chains | Payout manager | Inconsistent payouts, confusion | Manual operational procedures | Human error possible, no on-chain consistency check |
| Owner multi-sig behaves honestly | Owner (multi-signature wallet) | Malicious upgrade, fund drain, pause abuse | Multisig with threshold | Centralization; collusion or key compromise could bypass |
| Chainlink price feeds live and accurate | Chainlink oracle network | Wrong collateral valuation, bad debt | Redundant oracles, fallback TWAP | Oracle downtime or manipulation possible |
| CREATE2 addresses identical across chains | Factory deployer (protocol) | Predictable vault addresses (intended), but also enables replay | Deterministic salt | Replay risk if salt reused across chains |
| Payout manager sends identical Merkle roots to all chains | Payout manager (off-chain) | Claim state inconsistency | Not enforced on-chain | Attacker may claim on chain with different root (but usually root is same) |
| No concurrent payoutId reuse | Backend coordinator | Double payout | Not enforced on-chain | Backend bugs can lead to payoutId collisions |
