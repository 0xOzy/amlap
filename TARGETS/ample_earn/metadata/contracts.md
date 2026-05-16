# Contracts

## Core Protocol (4 chains)

### AmplePerspective
- Monad: `0x4b8057e5cdFAf53222580DFAc54f327fE11C2078`
- Base: `0x801ad3167d1578d5035a25425796b79cb4a31cba`
- Arbitrum: `0x4b8057e5cdfaf53222580dfac54f327fe11c2078`
- Katana: `0x4b8057e5cdfaf53222580dfac54f327fe11c2078`
- Role: ERC-4626 strategy perspective for Euler Earn meta-vault

### AmpleEarnFactory
- Monad: `0x9881464ade08eaea838d1ba06073a0c8f972b185` (proxy)
- Base: `0x62b304519ee30e205621920454c2802fb99dca67`
- Arbitrum: `0x9881464ade08eaea838d1ba06073a0c8f972b185`
- Katana: `0x9881464ade08eaea838d1ba06073a0c8f972b185`
- Role: Factory deploys AmpleEarn vaults

### AmpleEarnCrossChainRouter
- Monad: `0xc9086278b317d6316151945d720ce7b602fbe463`
- Base: `0xf132654d677034c804cfb6432d27526088deb0c5`
- Arbitrum: `0xcab6a41090e274efe7fe64cf0ec906f413686d36`
- Katana: `0x7beb2204fd629bf686ce85c640a5bcd66b392e65`
- Role: LayerZero cross-chain prize distribution

## External Dependencies
- EulerEarnFactory (Euler Finance)
- EulerEarn vault (ERC-4626)
- Euler EVK lending vaults
- LayerZero Endpoint
- Permit2
- EVC (Ethereum Vault Connector)
