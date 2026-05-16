# Call Graph Notes — Ample Earn

## AmpleEarnFactory
- `createAmpleEarn()` → deploys new ERC-4626 vault via CREATE2
- `setPerspective()` → updates AmplePerspective address
- `isStrategyAllowed()` → whitelist check
- `supportedPerspective()` → view current perspective
- `getVaultListLength()` / `getVaultListSlice()` → vault enumeration

## AmplePerspective (ERC-4626)
- `deposit(assets, receiver)` → mints shares
- `mint(shares, receiver)` → takes assets
- `withdraw(assets, receiver, owner)` → burns shares
- `redeem(shares, receiver, owner)` → returns assets
- `totalAssets()` → sum of assets in underlying Euler strategies
- `convertToShares()` / `convertToAssets()` → exchange rate

## AmpleEarnCrossChainRouter (LayerZero OApp)
- `claim(vault, payoutId, to)` → sends LayerZero message
- `_lzReceive()` → receives cross-chain message
- Peer validation: `OnlyPeer(eid, sender)`

## Euler Earn (underlying)
- EulerEarnFactory → deploys Earn vault
- Earn vault → allocates to EVK strategies
- EVK vault → lending/borrowing
