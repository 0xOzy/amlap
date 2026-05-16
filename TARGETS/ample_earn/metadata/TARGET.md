# Protocol Information

Name: Ample Earn
Chain: Monad, Base, Arbitrum, Katana
Category: Prize-Linked Savings / ERC-4626 Yield Aggregator
TVL: ~$4.46M (Base $4.33M, Arbitrum $118K, Katana $5.7K, Monad $4.7K)

Github: (tidak publik — verified on-chain only)
Docs: https://ample.money/ | https://docs.euler.finance/developers/euler-earn/
Bug Bounty: https://hackenproof.com/programs/ample-smart-contracts

Main Contracts (per chain):
- AmplePerspective (ERC-4626 vault perspective/strategy)
- AmpleEarnFactory (deploys AmpleEarn vaults via CREATE2)
- AmpleEarnCrossChainRouter (LayerZero cross-chain prize claim router)

Upgradeable: Yes — AmpleEarnFactory is proxy (Monad), others immutable
Oracle Dependencies: Euler Earn uses Chainlink via Euler vaults
Admin Roles: Owner (multi-sig), Guardian (circuit-breaker), Curator, Allocator
External Dependencies: Euler Earn (ERC-4626 meta-vault), LayerZero, Permit2, EVC
Known Risks: Third-party risk from Euler Earn strategies; cross-chain message validation
Previous Incidents: None reported
