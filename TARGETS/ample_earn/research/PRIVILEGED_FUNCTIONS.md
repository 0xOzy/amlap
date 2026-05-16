# Privileged Functions — Ample Earn

## AmpleEarnFactory
- `setPerspective(address)` — onlyOwner
- `transferOwnership(address)` — onlyOwner
- `acceptOwnership()` — onlyPendingOwner (2-step)
- Proxy upgrade (Monad) — onlyProxyAdmin

## AmpleEarnCrossChainRouter
- `setPeer(uint32 eid, bytes32 peer)` — onlyOwner
- Owner can change LayerZero peer addresses

## Euler Earn Vault (underlying)
- `setFee(uint256)` — onlyOwner
- `setFeeRecipient(address)` — onlyOwner
- `addStrategy(address)` — onlyCurator
- `removeStrategy(address)` — onlyCurator (timelocked)
- `setCap(address, uint256)` — onlyCurator (increase timelocked)
- `cancelTimelock()` — onlyGuardian or onlyOwner
- `transferOwnership(address)` — onlyOwner

## Emergency Risks
- Owner can set malicious perspective → fund misdirection
- Owner can change peer → cross-chain message hijack
- Curator can remove all strategies → fund lock
