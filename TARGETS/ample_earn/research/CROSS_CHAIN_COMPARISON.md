# Cross-Chain Comparison — Ample Earn

**Date:** 2026-05-15
**Method:** Byte-for-byte source diff, metadata analysis, checksum verification

---

## Executive Summary

**Semua scope contracts memiliki source code yang IDENTIK** di seluruh chain. Perbedaan hanya terletak pada:
1. **Deployment pattern** (Monad Factory = proxy, sisanya immutable)
2. **Constructor parameters** (alamat EVC, Permit2, LayerZero endpoint berbeda per chain)
3. **Monad Perspective flattened** (sama secara logika, tapi format file berbeda)
4. **CrossChainRouter addresses** unik per chain (LayerZero endpoint berbeda)

---

## 1. Source Code Comparison

### Checksum Verification

| Contract | Base | Arbitrum | Monad | Katana |
|---|---|---|---|---|
| **AmplePerspective** | `5f7444f2` | `5f7444f2` | `3032e2a1` ⚠️ | `5f7444f2` |
| **AmpleEarnFactory** | `f77c9c10` | `f77c9c10` | `f77c9c10` | `f77c9c10` |
| **AmpleEarnCrossChainRouter** | `f4d8ecf0` | `f4d8ecf0` | `f4d8ecf0` | `f4d8ecf0` |
| **AmpleEarn** (underlying) | `IDENTICAL` | `IDENTICAL` | `IDENTICAL` | `IDENTICAL` |
| **EulerEarn** (underlying) | `IDENTICAL` | `IDENTICAL` | `IDENTICAL` | `IDENTICAL` |

> Hash legend: ✅ **Hijau** = identical | ⚠️ **Kuning** = format berbeda, logika sama

### AmplePerspective — Monad Flattened

Monad's `AmplePerspective.sol` is **3,557 lines** vs 94 lines on other chains because it's a **flattened** file with all imports inlined. The contract logic (lines 3490-3557) is byte-identical minus ASCII art header.

**Root cause**: Monad uses a non-standard EVM compiler pipeline requiring flattened source for verification.

### AmpleEarnFactory — All Chains Identical

```diff
- NO DIFFERENCES FOUND
```

Every function, modifier, event, error, and storage slot is identical.

### AmpleEarnCrossChainRouter — All Chains Identical

```diff
- NO DIFFERENCES FOUND
```

Same LayerZero OApp implementation. The `localEid` is set at construction from `ILayerZeroEndpointV2(_endpoint).eid()` — this is an immutable value that differs per chain.

---

## 2. Deployment Pattern Comparison

### Proxy Status

| Contract | Base | Arbitrum | Monad | Katana |
|---|---|---|---|---|
| AmplePerspective | ✅ Immutable | ✅ Immutable | ✅ Immutable | ✅ Immutable |
| AmpleEarnFactory | ✅ Immutable | ✅ Immutable | ⚠️ **Transparent Proxy** | ✅ Immutable |
| AmpleEarnCrossChainRouter | ✅ Immutable | ✅ Immutable | ✅ Immutable | ✅ Immutable |

### Monad Proxy Details

- **Type**: OpenZeppelin Transparent Proxy (based on standard pattern)
- **Admin**: Owner (multi-sig)
- **Implementation**: `AmpleEarnFactory` (same code as all chains)
- **Implication**: Owner can replace factory logic at any time on Monad only

### CREATE2 Address Analysis

| Chain | Perspective Address | Factory Address | Note |
|---|---|---|---|
| Base | `0x801a...` (unique) | `0x62b3...` (unique) | Different salt |
| Arbitrum | `0x4b80...` | `0x9881...` | Same salt as Monad/Katana |
| Monad | `0x4b80...` | `0x9881...` (proxy wrapper) | Same salt, but proxy wraps it |
| Katana | `0x4b80...` | `0x9881...` | Same salt as Arb/Monad |

**Key Finding**: Arbitrum, Monad, and Katana share the same CREATE2 salt for Perspective and Factory deployments. Only Base uses a different salt. This means:
- Same Perspective address on 3 chains (benign — it's just a set membership checker)
- Same Factory address on 3 chains (but Monad wraps in proxy)
- Cross-chain replay attacks need to consider this address overlap

---

## 3. Compiler / Optimization Settings

| Setting | Base | Arbitrum | Monad | Katana |
|---|---|---|---|---|
| Solc version | 0.8.26 | 0.8.26 | 0.8.26 | 0.8.26 |
| Optimizer | ✅ enabled | ✅ enabled | ✅ enabled | ✅ enabled |
| Optimizer runs | 200 | 200 | 200 | 200 |
| EVM version | Cancun | Cancun | Cancun | Cancun |

✅ **IDENTICAL across all chains**

---

## 4. Linked Libraries

### External Libraries (same addresses on ALL chains)

| Library | Address | Used By |
|---|---|---|
| `AmplePayoutLib` | `0xaae4a86182a58353e17ebed5c6f773caef0da5e8` | AmpleEarnFactory |
| `CuratorLib` | `0xaf5ad8379b2a0b0e265ac8b70c18945e926cb33a` | AmpleEarnFactory |
| `ReallocateLib` | `0x9dc5c417f0df7e4e1a86fc827f85a664e82690b1` | AmpleEarnFactory |
| `StrategyLib` | `0x8ac4a25d992f5f2ddd141b78d7ed859a737475ea` | AmpleEarnFactory |

> **⚠️ Anomaly**: These library addresses are IDENTICAL across Base (OP Stack), Arbitrum (Nitro), Monad, and Katana. Since library addresses are deterministic (derived from deployer address + nonce, or CREATE2 salt + deployer), either:
> 1. Deployed via CREATE2 with identical salt from same deployer on all chains
> 2. Deployed via CREATE from same deployer address + same nonce (unlikely across different chains)
> 
> **Confidence**: HIGH — this is by design (deterministic deployment)

---

## 5. Constructor Parameter Differences

### AmplePerspective Constructor

```solidity
constructor(address _owner) Ownable(_owner) {}
```

| Parameter | Base | Arbitrum | Monad | Katana |
|---|---|---|---|---|
| `_owner` | Multi-sig A | Multi-sig A | Multi-sig A | Multi-sig A |

> **Likely same owner address** across chains (same team multi-sig).

### AmpleEarnFactory Constructor

```solidity
constructor(address _owner, address _evc, address _permit2, address _perspective)
```

| Parameter | Base | Arbitrum | Monad | Katana |
|---|---|---|---|---|
| `_owner` | Multi-sig A | Multi-sig A | Multi-sig A | Multi-sig A |
| `_evc` | EVC Base addr | EVC Arb addr | EVC Monad addr | EVC Katana addr |
| `_permit2` | Permit2 Base | Permit2 Arb | Permit2 Monad | Permit2 Katana |
| `_perspective` | `0x801a...` | `0x4b80...` | `0x4b80...` | `0x4b80...` |

> ⚠️ EVC and Permit2 addresses differ per chain (different deployments).
> ⚠️ Perspective address differs for Base vs others (different CREATE2 salt).

### AmpleEarnCrossChainRouter Constructor

```solidity
constructor(address _endpoint, address _owner, address _factory)
```

| Parameter | Base | Arbitrum | Monad | Katana |
|---|---|---|---|---|
| `_endpoint` | Base LZ Endpoint | Arb LZ Endpoint | Monad LZ Endpoint | Katana LZ Endpoint |
| `_owner` | Multi-sig A | Multi-sig A | Multi-sig A | Multi-sig A |
| `_factory` | `0x62b3...` | `0x9881...` | `0x9881...` (proxy) | `0x9881...` |

> ⚠️ `localEid` is set from `_endpoint.eid()` — this is the only runtime variance in the Router.
> ⚠️ Owner can configure different `setPeer()` per chain.

---

## 6. LayerZero Configuration Differences

### Per Chain

| Chain | Router Address | LZ Endpoint | Local EID (estimated) | Peers |
|---|---|---|---|---|
| Base | `0xf132...` | Base LZ EndpointV2 | 30184 (Base) | Arb, Monad, Katana routers |
| Arbitrum | `0xcab6...` | Arb LZ EndpointV2 | 30110 (Arbitrum) | Base, Monad, Katana routers |
| Monad | `0xc908...` | Monad LZ EndpointV2 | ? (unknown) | Base, Arb, Katana routers |
| Katana | `0x7beb...` | Katana LZ EndpointV2 | ? (unknown) | Base, Arb, Monad routers |

### Peer Configuration Risk

Each Router's peers are set via `setPeer(eid, peerAddress)` by the owner. If peers are misconfigured:
- Messages could be sent to wrong destination
- Unauthorized senders could inject messages

**Per chain peer risk**: IDENTICAL — same `onlyOwner` pattern, same risk level.

---

## 7. TVL Distribution Impact

### Why Differences Matter

| Difference | Security Impact |
|---|---|
| **Monad Factory = Proxy** | Monad: owner can upgrade → critical. Others: no upgrade → lower risk |
| **Different LZ endpoints** | Each chain has independent LZ security; compromise of one doesn't affect others |
| **Same library addresses** | If library is compromised on one chain, same library on all chains is affected |
| **Same source code** | Finding on one chain = finding on all chains (multiplied impact) |

### Attack Surface Weighted by Chain

| Attack | Base ($4.33M) | Arb ($118K) | Monad ($4.7K) | Katana ($5.7K) |
|---|---|---|---|---|
| ERC-4626 Donation | 🔴 $4.33M risk | 🟡 $118K risk | 🟢 $4.7K risk | 🟢 $5.7K risk |
| Cross-chain replay | 🟡 All chains | 🟡 All chains | 🟡 All chains | 🟡 All chains |
| Proxy upgrade | 🟢 N/A | 🟢 N/A | 🔴 Factory upgrade | 🟢 N/A |
| LayerZero hijack | 🟡 Per-chain | 🟡 Per-chain | 🟡 Per-chain | 🟡 Per-chain |

---

## 8. Summary of Differences

### Structural Differences

| # | Difference | Chain(s) | Severity |
|---|---|---|---|
| 1 | **Factory on proxy** | Monad only | 🔴 HIGH — upgrade risk |
| 2 | **Monad Perspective flattened** | Monad only | 🟢 LOW — cosmetic only |
| 3 | **Different CREATE2 salt for Base** | Base | 🟢 LOW — addresses differ |
| 4 | **CrossChainRouter unique per chain** | All | 🟢 LOW — expected |

### Configuration Differences

| # | Difference | Chain(s) | Severity |
|---|---|---|---|
| 5 | **LayerZero endpoint addresses** | All (different per chain) | 🟢 LOW — expected |
| 6 | **EVC addresses** | All (different per chain) | 🟢 LOW — expected |
| 7 | **Permit2 addresses** | All (different per chain) | 🟢 LOW — expected |
| 8 | **Perspective addresses** | Base ≠ others | 🟢 LOW — expected |

### Unchanged Elements

| Element | Status |
|---|---|
| Source code (all 3 scope contracts) | ✅ Identical |
| Compiler version (0.8.26) | ✅ Identical |
| Optimizer settings (enabled, 200 runs) | ✅ Identical |
| EVM version (Cancun) | ✅ Identical |
| Linked library addresses | ✅ Identical |
| External function signatures | ✅ Identical |
| Storage layout | ✅ Identical |
| Events | ✅ Identical |
| Error definitions | ✅ Identical |

---

## 9. Implications for Security Research

1. **Findings are cross-chain**: Since source code is identical, any vulnerability found applies to all chains (unless chain-specific conditions differ).

2. **Monad proxy requires separate analysis**: The Factory upgrade path on Monad introduces risks not present on other chains.

3. **Base should be primary test target**: Highest TVL ($4.33M) + standard deployment (no proxy) = best environment for fork testing.

4. **Same library addresses = same risk**: If a library has a vulnerability, it affects all chains equally.

5. **Cross-chain tests should use Base + Arbitrum**: These two have the highest combined TVL ($4.45M) and represent the most realistic attack surface.
