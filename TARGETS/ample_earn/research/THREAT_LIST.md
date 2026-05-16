# Threat Models — Ample Earn

**Date:** 2026-05-15  
**Target:** Ample Earn — Prize-linked savings on Euler Earn  
**Scope:** AmplePerspective, AmpleEarnFactory, AmpleEarnCrossChainRouter, EulerEarn, AmpleEarn, AmpleEarnReserve, AmplePayoutLib  
**Chains:** Base (TVL $4.33M), Arbitrum ($118K), Monad ($4.7K), Katana ($5.7K)  
**Template:** `templates/threat_template.md`

---

## Attacker Profiles

| ID | Profile | Capital | Skill | Goal |
|---|---|---|---|---|
| A1 | Cross-Chain Replayer | $5–$50K | LOW-MEDIUM | Claim payout N times across N chains |
| A2 | Griefing Attacker | $100–$1K | LOW | Disrupt protocol operations |
| A3 | Malicious Owner | Unlimited | HIGH | Steal all funds (requires multi-sig access) |
| A4 | Flashloan Arbitrageur | $100K–$500K | HIGH | Extract value via temporary price manipulation |

---

# Threat: T-01 — Cross-Chain Payout Replay

## Attack Surface

**Primary target:** `AmpleEarnCrossChainRouter.batchCrossChainClaimPayout()`  
**Underlying contracts:** `AmpleEarn.claimPayout()` (L288-296), `AmplePayoutLib.claimPayout()` (L93-117)  
**Storage layout:** `mapping(uint256 payoutId => PayoutPool payoutPool) public payoutPool` — NO vault/chain key

**Source code reference:**

```solidity
// AmpleEarn.sol:65 — payoutPool mapping
mapping(uint256 payoutId => PayoutPool payoutPool) public payoutPool;

// AmpleEarn.sol:288-296 — claim check uses ONLY payoutId
function isPayoutClaimed(uint256 payoutId, uint256 designatedRecipientIndex) ... {
    PayoutPool storage pool = payoutPool[payoutId];
    return (pool.claimMask & (uint256(1) << designatedRecipientIndex)) != 0;
}
```

The `claimMask` is stored per `payoutId` with **no vault or chain qualifier**. Each chain's EVM has independent storage. Therefore, `payoutPool[5]` on Base is a **different storage slot** than `payoutPool[5]` on Arbitrum — a claim on one chain does NOT update the other.

## Preconditions

1. **Same merkle root deployed on multiple chains**: Vault owner sets the same merkle root on both Base and Arbitrum (or any two chains).
2. **Same vault address on both chains**: Via CREATE2 determinism — confirmed for Arbitrum, Monad, and Katana (all share `0x9881...`). Base has a different address, but the attack works on any two chains where vault address matches.
3. **Attacker has a valid merkle proof**: From being a legitimate winner, or from monitoring mempool for a claim transaction that exposes the proof.

## Required Capital

| Chain Combination | Gas Cost | LayerZero Fee | Total |
|---|---|---|---|
| Base + Arbitrum | ~$5 | ~$15 | **~$20** |
| Base + Arbitrum + Monad | ~$10 | ~$30 | **~$40** |
| All 4 chains | ~$15 | ~$50 | **~$65** |

The capital requirement is **extremely low** — less than $100 to replay across all chains.

## Required Permissions

- **None**. The function `batchCrossChainClaimPayout()` is **public** and **payable**.
- Only needs: valid merkle proof, valid payoutId, valid designatedRecipientIndex
- These can be observed on-chain from a legitimate claim transaction.

## Exploit Sequence

**Step 1: Observe.** Monitor chain A for `claimPayout()` transactions. Extract: `payoutId`, `designatedRecipientLeaf`, `proof`.

**Step 2: Identify target chains.** Vault addresses are shared across Arbitrum, Monad, Katana via CREATE2. Each chain has independent `payoutPool` storage.

**Step 3: Submit claim on chain B.** Call `claimPayout(payoutId, leaf, proof)` directly on the vault contract on chain B (no need for CrossChainRouter).

**Step 4: Verify.** Check that `isPayoutClaimed()` returns `false` on chain B because `claimMask` on chain B was never set.

**Step 5: Repeat.** Submit on chain C, D, etc. Each chain has independent storage.

### Detailed Execution Path

```
1. Owner deploys merkleRoot R to both Base AND Arbitrum vaults
2. Attacker wins on Base → claims $500 on Base → claimMask Base updated
3. Attacker goes to Arbitrum vault (same merkleRoot R deployed)
4. Attacker calls claimPayout(5, leaf, proof) directly on Arbitrum vault
   → Arbitrum payoutPool[5].claimMask = 0x0 (NEVER touched)
   → isPayoutClaimed = false on Arbitrum
   → Claim succeeds → $500 paid from Arbitrum's payout reserve
   → $500 claimed twice from the same prize
```

This does NOT require CrossChainRouter at all — the attacker can call `claimPayout()` directly on the other chain's vault.

## Expected Outcome

| Skenario | Hasil |
|---|---|
| Single chain | Payout claimed exactly once ✅ |
| 2 chains with vault on both | **Payout claimed 2×** 🔴 |
| 3 chains with vault on both | **Payout claimed 3×** 🔴 |
| 4 chains with vault on all | **Payout claimed 4×** 🔴 |

**Profit per replay**: Prize amount minus ~$20 fees. If prize = $500, profit = $480 per additional chain.

## Mitigations

### Existing (Insufficient)
1. Bitmask (`claimMask`) — prevents same-chain replay ✅
2. `nonReentrant` on `claimPayout()` — prevents reentrancy ✅
3. Merkle proof verification — ensures only valid winners ✅

### Missing (Critical Gap)
1. **No vault key in payoutId namespace**: `payoutPool[payoutId]` should be `payoutPool[vault][payoutId]` or use a unique global payoutId across chains.
2. **No cross-chain claim coordination**: No mechanism to share claim state between chains.
3. **No minimum payoutId uniqueness check**: Owner can deploy same merkle root on multiple chains without restriction.

### Recommended Fix
```solidity
// Option A: Include vault address in payoutPool namespace
mapping(address vault => mapping(uint256 payoutId => PayoutPool)) public payoutPool;

// Option B: Use globally unique payoutId (chainId + payoutId)
function claimPayout(uint256 chainPayoutId, ...) {
    uint256 globalId = uint256(keccak256(abi.encodePacked(block.chainid, chainPayoutId)));
    ...
}
```

## Confidence

| Dimension | Rating | Rationale |
|---|---|---|
| **Source verification** | **VERY HIGH** | `payoutPool` mapping confirmed without vault/chain key in source code |
| **Storage isolation** | **VERY HIGH** | EVM guarantees per-chain storage isolation |
| **Executeability** | **HIGH** | ~$20 cost, valid proof needed but obtainable |
| **Likelihood** | **MEDIUM** | Requires merkle root deployed on ≥2 chains |
| **Overall** | **MEDIUM-HIGH** | |

---

# Threat: T-02 — Router Reentrancy via Refund Call

## Attack Surface

**Primary target:** `AmpleEarnCrossChainRouter.batchCrossChainClaimPayout()` (L89-133)  
**Vulnerable code:** L130 — `.call{value}` refund to `msg.sender` without `nonReentrant`  
**Source:**

```solidity
// AmpleEarnCrossChainRouter.sol — L89-133
function batchCrossChainClaimPayout(...) external payable {
    uint256 totalValueUsed;
    for (...) {
        // LayerZero message sending
        totalValueUsed += nativeFee;
    }
    // ... refund at the end
    if (msg.value > totalValueUsed) {
        (bool success,) = payable(msg.sender).call{value: msg.value - totalValueUsed}("");
        if (!success) revert TransferFailed();
    }
}
```

The function lacks a `nonReentrant` modifier. While state changes (LayerZero sends) happen BEFORE the refund call (CEI-like pattern), the refund `.call{value}` to `msg.sender` creates an external call opportunity.

## Preconditions

1. Attacker is a smart contract (not an EOA)
2. Attacker overpays for LayerZero fees (msg.value > total fees)
3. Attacker's `receive()` function re-enters `batchCrossChainClaimPayout()` or another function

## Required Capital

| Item | Cost |
|---|---|
| Gas for attack contract | ~$30 |
| Overpaid LayerZero fee | ~$20–$200 |
| **Total** | **~$50–$230** |

## Required Permissions

- **None** — function is `external payable`

## Exploit Sequence

1. Deploy contract with malicious `receive()` that calls `batchCrossChainClaimPayout()` again (or `claimPayout()`)
2. Send transaction with `msg.value` significantly higher than total fees (e.g., 2× needed)
3. First execution: send LayerZero messages, then refund call triggers `receive()`
4. Reentrant call: attempt to reenter `batchCrossChainClaimPayout()`

### Why This Is Partially Mitigated

- LayerZero sends already consumed some `msg.value` → second call has less gas available
- `claimPayout()` is `nonReentrant` — cannot double-claim
- State changes in first call already executed

### Remaining Risk

- Reentrant call could attempt to send duplicate LayerZero messages
- Gas griefing: first call's refund fails partially → DoS
- Cross-chain state inconsistency if messages are processed in unexpected order

## Expected Outcome

| Scenario | Result |
|---|---|
| Reenter `claimPayout()` | ✅ Blocked by nonReentrant |
| Reenter `batchCrossChainClaimPayout()` | ❓ Unclear — no protection, but limited utility |
| Gas griefing (refund fails) | 🟡 Excess value locked in contract |

**Maximum loss**: Gas fees + overpaid LayerZero fees (no direct fund loss).

## Mitigations

### Existing
1. `.call{value}` after state changes (CEI-like)
2. `claimPayout()` is `nonReentrant`

### Missing
1. **`nonReentrant` modifier on `batchCrossChainClaimPayout()`**
2. Consider using `_refund()` pattern from OApp instead of custom refund logic

### Recommended Fix
```solidity
function batchCrossChainClaimPayout(...) external payable nonReentrant {
    // ... existing logic
}
```

## Confidence

| Dimension | Rating | Rationale |
|---|---|---|
| **Source verification** | **VERY HIGH** | Confirmed no nonReentrant on function |
| **Executeability** | **MEDIUM** | Possible but limited profit |
| **Likelihood** | **LOW-MEDIUM** | Partially mitigated by CEI pattern |
| **Overall** | **MEDIUM** | |

---

# Threat: T-03 — Batch Partial Gas Griefing

## Attack Surface

**Primary target:** `AmpleEarnCrossChainRouter.batchCrossChainClaimPayout()` (L89-133)  
**Vulnerable pattern:** Loop over multiple claims in a single transaction

```solidity
for (uint256 i; i < claimData.length; i++) {
    // ... LayerZero _lzSend for each claim
    totalValueUsed += nativeFee;
}
```

## Preconditions

1. Multiple claims are bundled in a single `batchCrossChainClaimPayout()` call
2. `msg.value` is exactly or slightly above `totalValueUsed`
3. One of the destinations fails partially

## Required Capital

| Item | Cost |
|---|---|
| Gas for failed message | ~$5–$10 per destination |
| LayerZero fee per destination | ~$10–$20 |
| **Total** | **~$15–$30 per griefed message** |

## Required Permissions

- **None** — public function

## Exploit Sequence

1. Attacker sends `batchCrossChainClaimPayout()` with `msg.value` exactly matching total fees
2. First LayerZero send succeeds (fees consumed)
3. Second LayerZero send fails (insufficient gas simulation or endpoint issue)
4. Transaction reverts? Or partial success?

### Source Analysis

The function does NOT check return value of `_lzSend()`. If one send reverts, the entire transaction reverts (Solidity default). The refund check `msg.value > totalValueUsed` is also after all sends.

If `msg.value` is **less** than total fees, the function proceeds partway before reverting — potential partial state change? No, LayerZero sends are atomic per call.

## Expected Outcome

| Scenario | Result |
|---|---|
| All sends succeed | ✅ Claims processed |
| One send reverts | ❌ Entire tx reverts — no partial state |
| msg.value < fees | ❌ Refund after sends → but insufficient fees cause revert earlier |

**Risk**: LOW — attacker wastes ~$30, no direct fund loss.

## Mitigations

### Existing
- Solidity's atomic transaction behavior prevents partial execution
- LayerZero handles fee validation at endpoint level

### Missing
- No pull-based refund mechanism (excess fees stay in contract until explicitly withdrawn)

### Recommended Fix
Consider adding a `withdrawExcess()` function for stuck funds.

## Confidence

**LOW** — unlikely to be exploited meaningfully.

---

# Threat: T-04 — Malicious Perspective

## Attack Surface

**Primary target:** `AmpleEarnFactory.setPerspective(address)`  
**Privilege:** `onlyOwner`

```solidity
// AmpleEarnFactory.sol
function setPerspective(address _perspective) external onlyOwner {
    if (_perspective == address(0)) revert NotVerified();
    perspective = _perspective;
}
```

## Preconditions

1. Owner (multi-sig) is compromised or malicious
2. A fake perspective contract exists that returns `true` for any vault address

## Required Capital

| Item | Cost |
|---|---|
| Deploy fake perspective | ~$10 gas |
| (If multi-sig compromise) | External to protocol |

## Required Permissions

- **Owner (multi-sig)** — this is a privileged function

## Exploit Sequence

1. Owner deploys `FakePerspective` where `isVerified(x) = true` for all x
2. Owner calls `setPerspective(address(fakePerspective))`
3. Now `createAmpleEarn()` passes `isVerified()` check for ANY vault
4. Owner deploys vault with malicious strategy that steals deposits
5. Users deposit USDC → funds go to malicious strategy → stolen

## Expected Outcome

**CRITICAL** — complete loss of user deposits on subsequent vault deployments.

| Scenario | Result |
|---|---|
| Compromised multi-sig | 🔴 All future vault funds stolen |
| Honest multi-sig | ✅ No impact |

**Existing vaults are NOT affected** — they already have their `perspective` reference (immutable in vault constructor).

## Mitigations

### Existing
1. Multi-sig requirement for owner operations (social mitigation)
2. Immutable perspective reference in deployed vaults

### Missing
1. No timelock on `setPerspective()`
2. No event monitoring suggestion

### Recommended Fix
```solidity
// Add timelock
function setPerspective(address _perspective) external onlyOwner {
    pendingPerspective = _perspective;
    perspectiveTimelock = block.timestamp + 3 days;
}
function acceptPerspective() external onlyOwner {
    if (block.timestamp < perspectiveTimelock) revert TooEarly();
    perspective = pendingPerspective;
}
```

## Confidence

**LOW** (requires multi-sig compromise, which is external to smart contract security).

---

# Threat: T-05 — Monad Factory Proxy Upgrade

## Attack Surface

**Primary target:** Monad's `AmpleEarnFactory` behind OpenZeppelin Transparent Proxy  
**Privilege:** `ProxyAdmin` (owner) can call `upgradeTo(address)`  
**Chain-specific:** Only affects Monad chain

## Preconditions

1. Owner (multi-sig) on Monad is compromised or malicious
2. A malicious implementation contract exists

## Required Capital

| Item | Cost |
|---|---|
| Deploy malicious implementation | ~$20 gas |
| Upgrade call | ~$5 gas |

## Required Permissions

- **Owner (multi-sig)** on Monad chain

## Exploit Sequence

1. Owner deploys `MaliciousAmpleEarnFactory` with backdoor functions
2. Owner calls `upgradeTo(address(maliciousImpl))` on proxy
3. New implementation takes effect immediately

### Attack Vectors via Malicious Factory

| Vector | Description |
|---|---|
| `setPerspective(address(0))` | Bypass perspective check for new vaults |
| Steal CREATE2 salt | Control what vaults are deployed |
| Fake `isVault()` | Return true for any address, tricking Router |
| `selfdestruct()` | Destroy the factory entirely |

## Expected Outcome

| Scenario | Result |
|---|---|
| Compromised multi-sig on Monad | 🔴 **Factory compromised** — all new Monad vault deployments are backdoored |
| Honest multi-sig | ✅ No impact |

**Note**: TVL on Monad is only $4.7K, so economic impact is minimal compared to other chains.

## Mitigations

### Existing
1. Multi-sig requirement for owner operations
2. Existing vaults on Monad already deployed — not affected by factory upgrade

### Recommended Fix
1. Remove proxy and deploy factory as immutable (like other chains)
2. Or use a timelock on proxy upgrades (e.g., OpenZeppelin's `TimelockController`)

## Confidence

**LOW** (requires multi-sig compromise, but the vulnerability surface exists uniquely on Monad).

---

# Threat: T-06 — LayerZero Peer Hijack

## Attack Surface

**Primary target:** `AmpleEarnCrossChainRouter.setPeer(uint32 eid, bytes32 peer)`  
**Privilege:** `onlyOwner`

```solidity
// Inherited from OApp.sol
function setPeer(uint32 eid, bytes32 peer) public virtual onlyOwner {
    peers[eid] = peer;
}
```

## Preconditions

1. Owner (multi-sig) is compromised or malicious
2. Valid destination endpoint IDs are known

## Required Capital

| Item | Cost |
|---|---|
| Deploy endpoint impersonator | ~$50 gas |
| SetPeer transaction | ~$5 gas |

## Required Permissions

- **Owner (multi-sig)**

## Exploit Sequence

1. Owner changes `peers[eid]` to point to attacker-controlled contract
2. Cross-chain payout claims are now routed to attacker's destination
3. LayerZero delivers messages containing payout instructions to attacker's contract
4. Attacker's contract simulates valid vault behavior → claims payouts meant for legitimate users

## Expected Outcome

| Scenario | Result |
|---|---|
| Compromised multi-sig | 🔴 All cross-chain payouts hijacked |
| Honest multi-sig | ✅ No impact |

**Maximum loss**: Value of all pending cross-chain payouts (depends on prize pool state).

## Mitigations

### Existing
1. Multi-sig requirement
2. LayerZero EndpointV2 security stack (optional DVN verification)

### Recommended Fix
1. Multi-sig timelock on `setPeer()`
2. Event monitoring for peer changes
3. Consider using immutable peers or a multisig-only role

## Confidence

**LOW** (requires multi-sig compromise).

---

# Threat: T-07 — Accounting Drift via Flashloan Strategy Manipulation

## Attack Surface

**Primary target:** `EulerEarn` → underlying Euler EVK strategies  
**Secondary target:** `AmpleEarn` vault share pricing  
**Attack vector:** Flashloan manipulates `previewRedeem()` of an EVK strategy temporarily

## Preconditions

1. An Euler EVK strategy has manipulable share pricing (e.g., thin liquidity pool)
2. Flashloan liquidity exists on the chain
3. The vault has sufficient depositors to make manipulation profitable

## Required Capital

| Chain | Flashloan Required | Total | Profit Potential |
|---|---|---|---|
| Base ($4.33M) | $1M+ | HIGH | LOW |
| Arbitrum ($118K) | $50K+ | MEDIUM | LOW |
| Monad ($4.7K) | $2K+ | LOW | LOW |
| Katana ($5.7K) | $2K+ | LOW | LOW |

## Required Permissions

- **None** — flashloan is permissionless

## Exploit Sequence

1. Take flashloan of USDC from Aave or similar
2. Deposit into target EVK strategy to manipulate `previewRedeem()`
3. Deposit into AmpleEarn vault at manipulated rate
4. Withdraw from AmpleEarn at new rate after manipulation subsides
5. Repay flashloan + keep profit

### Why This Is Hard

- `nonReentrant` on deposit/withdraw prevents flashloan within same tx
- Strategy share price manipulation requires significant capital
- `VIRTUAL_AMOUNT = 1e6` dilutes share price changes
- `_accruedFeeAndAssets()` absorbs temporary drops via `lostAssets`

## Expected Outcome

| Scenario | Result |
|---|---|
| Successful manipulation | 🟡 Extract small value, high cost |
| Failed manipulation | 🔴 Flashloan fee lost |

**Overall**: Not economically viable on any chain.

## Mitigations

### Existing (Strong)
1. `VIRTUAL_AMOUNT` inflation protection
2. `nonReentrant` on all deposit/withdraw functions
3. `lostAssets` buffer absorbs temporary losses
4. Multi-strategy diversification reduces single strategy impact

### Recommended
1. Monitor strategy share price deviations (off-chain)

## Confidence

**LOW** — economically unviable due to existing protections and high capital requirements.

---

## Threat Priority Matrix

| ID | Threat | Attacker | Exploitability | Impact | Priority |
|---|---|---|---|---|---|
| **T-01** | **Cross-Chain Payout Replay** | A1 | **MEDIUM-HIGH** | **CRITICAL** | 🔴 **P0** |
| T-02 | Router Reentrancy | A2 | MEDIUM | MEDIUM | 🟡 P1 |
| T-03 | Batch Partial Gas Griefing | A2 | LOW | LOW | 🟢 P3 |
| T-04 | Malicious Perspective | A3 | LOW | CRITICAL | 🟡 P2 |
| T-05 | Monad Proxy Upgrade | A3 | LOW | CRITICAL | 🟡 P2 |
| T-06 | LZ Peer Hijack | A3 | LOW | HIGH | 🟡 P2 |
| T-07 | Accounting Drift | A4 | LOW | LOW | 🟢 P3 |

---

## Recommended Next Steps (by Priority)

1. **🔴 P0 — T-01**: Fork test: deploy same merkle root on Base + Arbitrum, claim on both chains to verify cross-chain replay
2. **🟡 P1 — T-02**: Add `nonReentrant` to `batchCrossChainClaimPayout()`
3. **🟡 P2 — T-04, T-05, T-06**: Review multi-sig security, propose timelocks on privileged functions
4. **🟢 P3 — T-03, T-07**: Low priority, no immediate action needed

---

*Reformatted from `THREAT_LIST.md` using `templates/threat_template.md`.*
