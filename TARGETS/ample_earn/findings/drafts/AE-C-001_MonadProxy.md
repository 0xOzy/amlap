# AE-C-001: Monad Factory Proxy — No Timelock on Upgrade

## Severity

**🟠 MEDIUM**

## Summary

`AmpleEarnFactory` on Monad is the **only chain** where the factory contract is deployed behind an OpenZeppelin Transparent Proxy. This means the owner (multi-sig) can `upgradeTo()` a new implementation at any time without a timelock. While the current TVL on Monad is only $4.7K, an upgraded implementation could:
- Change the `perspective` address permanently
- Deploy vaults with malicious strategy validation
- Potentially affect cross-chain trust assumptions

## Detail

Source code is identical across all chains, but deployment pattern differs:

| Chain | Factory Deployment | Upgradeable? |
|---|---|---|
| Base | Immutable (direct deployment) | ❌ No |
| Arbitrum | Immutable | ❌ No |
| **Monad** | **Transparent Proxy** | **✅ Yes — no timelock** |
| Katana | Immutable | ❌ No |

## Impact Assessment

- **Existing vaults**: NOT affected — storage (including `perspective` address) is preserved across upgrades
- **New vaults**: COULD be affected — if implementation changes `perspective`, new vaults use malicious validation
- **Cross-chain escalation**: Blocked by LayerZero DVN verification + immutable factories on other chains
- **TVL at risk**: $4.7K (Monad only) — insufficient incentive for multi-sig compromise

## Recommendation

1. **Make factory immutable** (preferred) — revoke proxy admin role or selfdestruct proxy admin
2. **Add timelock** (minimum) — 7-day delay on `upgradeTo()` with guardian oversight
3. **Document** — Clearly communicate to users that Monad deployment is upgradeable

## Confidence

**HIGH** — Source code analysis confirmed proxy pattern; on-chain verification needed for proxy admin address.

## Validation Status

| Item | Status |
|---|---|
| Source code analysis | ✅ **Verified** — proxy in `proxies.json` |
| On-chain verification | ⏳ **Pending** — need admin address + timelock check |
