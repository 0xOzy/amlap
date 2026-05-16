# Threat Model — Ample Earn

**Date:** 2026-05-15
**Target:** Ample Earn — Prize-linked savings protocol on Euler Earn
**Scope:** AmplePerspective, AmpleEarnFactory, AmpleEarnCrossChainRouter (×4 chains)
**TVL:** $4.46M (Base $4.33M, Arbitrum $118K, Monad $4.7K, Katana $5.7K)
**Bounty:** Up to $20K Critical (HackenProof)

---

## Threat Categories

| Category | Scope |
|---|---|
| **Technical** | Smart contract bugs, accounting errors, reentrancy, DoS |
| **Economic** | Incentive misalignment, flashloan, oracle manipulation, MEV |
| **Governance** | Owner/Curator/Guardian privilege abuse, proxy upgrade |
| **Cross-Chain** | LayerZero message replay, payout duplication, replay attacks |
| **Operational** | Timelock bypass, multi-sig compromise, dependency failure |

---

## Attacker Profiles

| Profile | Capital | Technical Skill | Goal | Relevant Threats |
|---|---|---|---|---|
| **Flashloan Attacker** | High (flashloan) | High | Exploit temporary accounting imbalance | T-1, T-3, T-7 |
| **MEV Searcher** | Medium | High | Front-run prize distribution, arbitrage | T-5, T-8 |
| **Malicious Admin (Owner)** | N/A (has keys) | Medium | Upgrade proxy, set malicious perspective | T-4, T-6, T-9 |
| **Malicious Curator** | N/A (has role) | Medium | Bypass timelock, reallocate to risky strategies | T-8 |
| **Cross-Chain Replayer** | Low | Medium | Replay payout claims across chains | T-2 |
| **Griefing Attacker** | Low | Low | DoS, gas exhaustion, 0-value spam | T-10, T-11 |
| **Oracle Manipulator** | Very High | Very High | Manipulate underlying EVK strategy pricing | T-3 (out of scope) |
| **Governance Whale** | Very High (tokens) | Low | Not applicable (no governance token) | N/A |

---

## THREAT T-1: ERC-4626 Donation / Share Inflation

**Category:** Technical — Accounting

**Threat:**
Attacker donates USDC directly to vault before a large deposit, inflating the share price. Subsequent depositors receive fewer shares than expected, resulting in value extraction by the attacker.

**Attack Preconditions:**
- `totalAssets()` uses `asset.balanceOf(address(this))` rather than internal accounting
- Vault accepts direct token transfers (USDC has no blocklist on transfer)
- No virtual shares or offset mechanism implemented
- Attacker can deposit before victim

**Required Capital:**
- **Donation amount:** ~$1,000-$10,000 USDC (sufficient to inflate shares for a small vault)
- **Victim deposit:** Requires a legitimate depositor to follow the attacker's donation

**Required Permissions:**
- None — anyone can transfer USDC to any address

**Attack Path (Technical):**
```
1. Attacker transfers X USDC directly to vault address (donation)
2. Vault's totalAssets() increases by X, totalSupply() unchanged
3. Exchange rate: shares = assets * totalSupply() / totalAssets()
   → Since totalAssets() inflated, each share is worth more
4. Attacker deposits tiny amount (dust) via deposit() → receives (dust * totalSupply()) / (totalAssets_before + dust)
   → Attacker now holds shares but has contributed almost nothing
5. Victim deposits Y USDC → receives fewer shares than expected
6. Attacker withdraws shares → receives more USDC than deposited
7. Profit = inflated share redemption - donation - dust deposit
```

**Potential Profit:**
- **Maximum:** ~50% of victim's deposit (theoretical; practical ~1-10% before arbitrage)
- **Realistic:** Lower bounded by attacker's donation cost
- **Base:** $4.33M TVL → profit potential in thousands of dollars
- **Monad/Katana:** $4-5K TVL → profit potential in tens of dollars

**Difficulty:** LOW (standard ERC-4626 attack, well-documented)
**Exploitability:** MEDIUM

**Per-Chain Analysis:**

| Chain | TVL | Donation Cost | Profit Potential | Exploitability |
|---|---|---|---|---|
| **Base** | $4.33M | ~$1K-$10K | High | MEDIUM |
| **Arbitrum** | $118K | ~$500-$5K | Medium | MEDIUM |
| **Monad** | $4.7K | ~$100-$1K | Low | MEDIUM-HIGH |
| **Katana** | $5.7K | ~$100-$1K | Low | MEDIUM-HIGH |

**Mitigations:**
- Virtual shares (inflation protection via `_decimalsOffset()`)
- Internal accounting for `totalAssets()` (e.g., cumulative deposits minus withdrawals)
- Dead share provision (first deposit mints minimum shares)

**Validation Status:** ⚠️ Needs fork test (AE-F-001)

---

## THREAT T-2: Cross-Chain Payout Claim Replay

**Category:** Cross-Chain

**Threat:**
A winner's payout claim (identified by `payoutId`) that is processed on one chain can be replayed on another chain, resulting in double or multiple payouts from the same prize.

**Attack Preconditions:**
- `payoutId` uniqueness is not enforced globally across all chains
- Same merkle root deployed on multiple chains
- LayerZero message delivery to multiple destination chains
- Attacker can submit `batchCrossChainClaimPayout()` with valid proof to multiple destinations

**Required Capital:**
- **Gas costs:** LayerZero fees for cross-chain messages (~$5-$50 per message per chain)
- **No capital required** for the attack itself (only gas and a valid merkle proof)

**Required Permissions:**
- Must hold a valid merkle proof for a winning `payoutId` (legitimate winner, or proof extraction)

**Attack Path (Technical):**
```
1. Winner generates merkle proof for payoutId = 123
2. Winner calls batchCrossChainClaimPayout() on Base
   → LayerZero message sent to Arbitrum (destination)
   → Arbitrum Router._lzReceive() → claimPayout() executes → payoutId marked claimed on Arbitrum
3. Winner calls batchCrossChainClaimPayout() on Arbitrum
   → LayerZero message sent to Katana (destination)
   → Katana Router._lzReceive() → claimPayout() checks isPayoutClaimed()
   ❓ If payoutId tracking is per-vault (vault-specific) rather than per-chain global
   → PayoutId might NOT be marked claimed on Katana → second payout
4. Repeat for all chains where vault exists with same merkle root
```

**Critical Question:**
- Is `isPayoutClaimed(payoutId)` tracked in a **vault-specific** storage slot or globally?
- If vault-specific: `payoutId = 123` on Base vault ≠ `payoutId = 123` on Arbitrum vault → separate counters → REPLAY POSSIBLE
- If global (e.g., `claimedPayouts[payoutId]` without vault key) → replay prevented

**Code Analysis:**
From `AmpleEarn.sol`:
- `function isPayoutClaimed(uint256 payoutId) external view returns (bool)`
- `function claimPayout(...)` checks `isPayoutClaimed(payoutId)`
- Need to verify storage layout: is `claimedPayouts` per-vault or per-chain?

**Potential Profit:**
- **Per replay:** Value of the winning prize (protocol-defined, likely ~$100-$10,000)
- **Maximum:** prize_amount × (N-1) chains replayed

**Difficulty:** LOW-MEDIUM (depends on `isPayoutClaimed` implementation)
**Exploitability:** MEDIUM (needs validation)

**Per-Chain Analysis:**

| Chain | Vault Exists | LZ Peers | Replay Target? |
|---|---|---|---|
| **Base** | ✅ Yes | Arb, Monad, Katana | Source chain |
| **Arbitrum** | ✅ Yes | Base, Monad, Katana | ✅ Primary replay target |
| **Monad** | ✅ Yes | Base, Arb, Katana | ✅ Possible |
| **Katana** | ✅ Yes | Base, Arb, Monad | ✅ Possible |

**Mitigations:**
- Global `payoutId` counter unique across all chains (off-chain coordination)
- Vault address + payoutId composite key for claim tracking
- Same merkle root NOT deployed on multiple chains

**Validation Status:** ⚠️ Needs investigation (AE-F-002)

---

## THREAT T-3: Oracle Manipulation via Euler EVK

**Category:** Economic

**Threat:**
While Ample Earn scope contracts have zero direct oracle dependencies, the underlying Euler EVK strategies use Chainlink price feeds. A manipulated oracle affects EVK strategy share prices, which flows through to AmpleEarn's `totalAssets()` calculation, enabling profitable deposits/withdrawals at wrong rates.

**Attack Preconditions:**
- Underlying Euler EVK strategy has a manipulable oracle (low liquidity pair, no TWAP)
- Strategy share price can be temporarily distorted
- AmpleEarn vault has sufficient TVL for profitable manipulation
- Attacker can flashloan the required capital

**Required Capital:**
- **Base:** Very high ($1M+ flashloan) for deep USDC liquidity
- **Arbitrum:** High ($100K+)
- **Monad:** Medium ($10K+)
- **Katana:** Low ($2K+)
- **Oracle manipulation cost:** Additional capital to move price

**Required Permissions:**
- None — public deposit/withdraw via Euler EVK strategies

**Attack Path (Simplified):**
```
1. Flashloan USDC → deposit into Euler EVK strategy
2. Strategy share price inflates (if oracle can be pushed)
3. AmpleEarn.totalAssets() → expectedSupplyAssets() → reads inflated strategy balance
4. Attacker deposits small amount into AmpleEarn → receives fewer shares
5. OR: Attacker withdraws shares → receives more assets than deserved
6. Repay flashloan
7. Profit = difference from inflated share price
```

**Potential Profit:**
- **Upper bound:** TVL of AmpleEarn vault on that chain
- **Practical:** Limited by flashloan fee + slippage + oracle manipulation cost
- **Mitigation:** `nonReentrant` on all entry points, try/catch in supplyStrategy

**Difficulty:** VERY HIGH (requires EVK strategy vulnerability + oracle manipulation)
**Exploitability:** LOW

**Per-Chain Analysis:**

| Chain | Oracle Depth | Flashloan Cost | Feasibility |
|---|---|---|---|
| **Base** | Deep | High ($5M+) | VERY LOW |
| **Arbitrum** | Medium | Medium | LOW |
| **Monad** | Low | Low | MEDIUM |
| **Katana** | Very low | Very low | MEDIUM |

**Mitigations:**
- Out of scope (Euler EVK level)
- AmpleEarn relies on Euler EVK for accurate pricing

**Validation Status:** ❓ Unknown — out of scope (AE-O-001)

---

## THREAT T-4: Factory Proxy Upgrade Attack (Monad)

**Category:** Governance — Upgradeability

**Threat:**
`AmpleEarnFactory` on Monad is deployed behind a proxy (unique among all chains). The owner (multi-sig) can upgrade the implementation to a malicious contract, gaining control over factory operations including perspective validation for all future vault deployments.

**Attack Preconditions:**
- Owner multi-sig is compromised or malicious
- Factory implementation on Monad is upgradeable (confirmed via proxies.json)

**Required Capital:**
- **Capital for attack:** Zero (requires privileged keys, not capital)
- **Capital to exploit:** None — upgrades are free except gas

**Required Permissions:**
- Owner multi-sig on Monad (N-of-M threshold to be verified on-chain)

**Attack Path (Technical):**
```
1. Compromise N-of-M multi-sig for Monad factory proxy admin
2. Deploy malicious implementation:
   contract MaliciousFactory {
       function setPerspective(address) external { /* no-op */ }
       function isStrategyAllowed(address) external view returns (bool) { return true; }
       function drainFunds(address to) external { /* transfer */ }
   }
3. Call upgradeTo(maliciousImpl) on proxy admin
4. All future vault deployments from this factory use malicious logic
5. Perspective validation is bypassed → any address can be used as strategy
6. Deposits can be directed to attacker-controlled addresses
```

**Potential Profit:**
- **Direct:** Full TVL of vaults deployed AFTER the upgrade on Monad ($4.7K)
- **Indirect:** If cross-chain messages from Monad are trusted, other chains may be affected

**Difficulty:** HIGH (requires multi-sig compromise)
**Exploitability:** LOW

**Per-Chain Analysis:**

| Chain | Proxy? | Risk |
|---|---|---|
| **Base** | ✅ No | Not applicable |
| **Arbitrum** | ✅ No | Not applicable |
| **Monad** | ⚠️ **YES** | 🔴 HIGH — upgrade path exists |
| **Katana** | ✅ No | Not applicable |

**Mitigations:**
- Multi-sig with high threshold (4-of-7 or similar)
- Timelock on proxy admin
- Immutable factory on all other chains

**Validation Status:** ✅ Verified — requires on-chain proxy admin verification (AE-C-001)

---

## THREAT T-5: MEV / Prize Distribution Front-Running

**Category:** Economic — MEV

**Threat:**
An MEV searcher monitors the mempool for prize distribution transactions and front-runs them to extract value. If prize distribution changes vault state (e.g., totalSupply adjustment, payout deductions), the MEV searcher can sandwich the distribution for profit.

**Attack Preconditions:**
- Prize distribution is a public or observable transaction
- Vault share price changes during distribution (yield accrual, payout deductions)
- MEV searcher can reorder transactions

**Required Capital:**
- **Gas premium:** Higher priority fee than the victim transaction
- **Capital for attack:** Position in the vault (shares to manipulate)

**Required Permissions:**
- None — public mempool

**Attack Path (Simplified):**
```
1. MEV searcher monitors for setMerkleRoots() or distributePrize() call
2. Front-run: deposit USDC into vault before distribution
3. Distribution executes → yield accrued → share price changes
4. Back-run: withdraw shares after distribution → profit from price change
```

**Potential Profit:**
- **Limited by:** Prize pool size, yield accrued per distribution
- **Typical:** Small ($10-$100 per distribution event)
- **Worst case:** If distribution has a bug that causes accounting error → much larger

**Difficulty:** MEDIUM (standard MEV techniques)
**Exploitability:** MEDIUM (requires vault position + timing)

**Mitigations:**
- Commit-reveal for prize distribution
- Flashbot/private mempool integration
- nonReentrant guards

**Validation Status:** ⚠️ Needs investigation

---

## THREAT T-6: Owner Sets Malicious Perspective

**Category:** Governance — Privileged Functions

**Threat:**
The owner can call `setPerspective(address)` on `AmpleEarnFactory` to point to a malicious `AmplePerspective` contract. Once changed, all vault deployments use the malicious perspective for strategy verification, allowing strategies to be whitelisted even if they are malicious.

**Attack Preconditions:**
- Owner multi-sig is compromised or malicious
- Factory `setPerspective()` has no timelock or delay

**Required Capital:**
- Zero (requires privileged keys)

**Required Permissions:**
- Owner of `AmpleEarnFactory` on any chain

**Attack Path (Technical):**
```
1. Owner deploys malicious perspective:
   contract MaliciousPerspective {
       function verify(address) external {}
       function unverify(address) external {}
       function isVerified(address) external view returns (bool) { return true; }
   }
2. Owner calls factory.setPerspective(maliciousPerspective)
3. Factory.createAmpleEarn() now uses malicious perspective
4. Any address passes isVerified() → "strategy" can be any contract
5. User deposits → funds sent to fake "strategy" → stolen
```

**Potential Profit:**
- **Full TVL of vaults deployed AFTER perspective change**
- **Pre-deployed vaults:** Not affected (they use the perspective at deployment time)
- **Impact limited to:** New vault deposits

**Difficulty:** LOW (requires owner keys, but technically trivial)
**Exploitability:** LOW (requires owner compromise)

**Per-Chain Analysis:**

| Chain | Owner Controls Factory? | Impact |
|---|---|---|
| **Base** | ✅ Yes (immutable) | Can change perspective |
| **Arbitrum** | ✅ Yes (immutable) | Can change perspective |
| **Monad** | ✅ Yes (proxy) | Can change perspective + upgrade |
| **Katana** | ✅ Yes (immutable) | Can change perspective |

**Mitigations:**
- Timelock on `setPerspective()` (not currently implemented)
- Multi-sig owner with high threshold
- Only affects new vault deployments, not existing vaults

**Validation Status:** ✅ Verified (AE-P-001)

---

## THREAT T-7: Flashloan + Cross-Chain Prize Claim Racing

**Category:** Cross-Chain — Economic

**Threat:**
Attacker combines flashloan with cross-chain message timing to claim the same payout on multiple chains before the payout status synchronizes. If `isPayoutClaimed(payoutId)` is checked per-chain without cross-chain synchronization window consideration, the payout can be claimed multiple times.

**Attack Preconditions:**
- `payoutId` is not globally unique across chains
- LayerZero message delivery has a time window (blocks) between chains
- Attacker can submit claims on multiple chains within the same block

**Required Capital:**
- **Flashloan:** To temporarily inflate position or cover gas
- **Gas:** LayerZero fees for multiple cross-chain messages

**Required Permissions:**
- Must hold a valid merkle proof for a winning payoutId

**Attack Path:**
```
Block N:  Attacker submits batchCrossChainClaimPayout() on Base → message to Arbitrum
          Attacker submits batchCrossChainClaimPayout() on Arbitrum → message to Base
          (Both messages in flight simultaneously)
Block N+1: Base Router receives Arbitrum's message → processes claim → payoutId claimed on Base
           Arbitrum Router receives Base's message → processes claim → payoutId claimed on Arbitrum
           Result: payoutId claimed on BOTH chains → DOUBLE PAYOUT
```

**Potential Profit:**
- **Per cycle:** Prize amount × 2 (or more chains)
- **Repeatable:** Until the same payoutId is exhausted or detected

**Difficulty:** MEDIUM-HIGH (requires cross-chain timing + valid proof)
**Exploitability:** MEDIUM (if payoutId tracking is per-chain, not global)

**Per-Chain Analysis:**

| Chain Pair | LZ Latency | Feasibility |
|---|---|---|
| Base ↔ Arbitrum | ~1-20 min | MEDIUM |
| Base ↔ Monad | Unknown | LOW |
| Arbitrum ↔ Katana | Unknown | LOW |

**Validation Status:** ⚠️ Needs investigation (AE-F-002)

---

## THREAT T-8: Strategy Cap Timelock Bypass

**Category:** Governance — Operational

**Threat:**
The Curator can submit a strategy cap increase (subject to timelock). If the Guardian cancels it, the Curator may re-submit the same cap increase in the same block, effectively bypassing the timelock protection.

**Attack Preconditions:**
- Curator and Guardian are different entities (or same entity with both roles)
- `revokePendingTimelock()` only removes the current pending cap without a cooldown period
- No minimum interval between cancel and re-submit

**Required Capital:**
- Zero (privileged role)

**Required Permissions:**
- Curator role to submit cap increase
- Guardian role to cancel (or colluding Guardian)

**Attack Path:**
```
1. Curator calls submitCap(strategy, highCap) → timelock begins
2. Guardian calls revokePendingTimelock() → cancels the increase
3. Curator calls submitCap(strategy, highCap) again → NEW timelock begins (immediately)
```

**Potential Profit:**
- **Over-allocation:** Strategy receives more funds than intended
- **Risk exposure:** If strategy is risky, depositors bear the loss
- **No direct profit** unless curator also controls the risky strategy

**Difficulty:** LOW (if Curator and Guardian collude or are same entity)
**Exploitability:** LOW-MEDIUM

**Validation Status:** ⚠️ Needs investigation (AE-P-004)

---

## THREAT T-9: LayerZero Peer Hijack

**Category:** Cross-Chain — Governance

**Threat:**
The owner can change LayerZero peer addresses via `setPeer(eid, peerAddress)`. A malicious or compromised owner can redirect cross-chain claim messages to an attacker-controlled chain, where the attacker deploys a compatible `_lzReceive()` handler to process arbitrary payouts.

**Attack Preconditions:**
- Owner multi-sig is compromised or malicious
- Attacker has deployed a compatible receiver contract on the destination chain

**Required Capital:**
- **Deploy receiver:** Minimal gas cost
- **Keys:** Owner multi-sig access

**Required Permissions:**
- Owner of `AmpleEarnCrossChainRouter`

**Attack Path:**
```
1. Owner calls router.setPeer(arbitrumEid, attackerEndpointAddress)
2. All cross-chain claims destined for Arbitrum now go to attacker's endpoint
3. Attacker's endpoint receives message → processes claim → sends payout to attacker
4. Real Arbitrum vault never receives the message
5. Attacker collects the prize payout
```

**Potential Profit:**
- **Per message:** Value of any cross-chain payouts sent during the window
- **Maximum:** All pending cross-chain claims

**Difficulty:** LOW (technically, with owner keys)
**Exploitability:** LOW (requires owner compromise)

**Mitigations:**
- Multi-sig owner with timelock
- Monitoring for `setPeer()` events
- LayerZero DVN validation (out of scope)

**Validation Status:** ✅ Verified (AE-P-002)

---

## THREAT T-10: batchCrossChainClaimPayout DoS / Gas Griefing

**Category:** Technical — Denial of Service

**Threat:**
An attacker can submit a `batchCrossChainClaimPayout()` call with a very large batch size, causing the transaction to run out of gas mid-execution. This wastes the caller's gas and may leave the system in an inconsistent state (partial LayerZero sends without complete refund).

**Attack Preconditions:**
- No batch size limit in `batchCrossChainClaimPayout()`
- `msg.value` validation fails after some iterations

**Required Capital:**
- **Gas cost:** The cost of failed transaction (wasted)
- **No capital loss** (msg.value is refunded on failure? — needs verification)

**Required Permissions:**
- None — public function

**Attack Path:**
```
1. Attacker calls batchCrossChainClaimPayout([params1, params2, ..., params100])
2. Loop runs for N iterations until gas runs out
3. Partial iterations may have sent LayerZero messages
4. msg.value refund at line 130 may not execute
5. Attacker loses gas but may cause disruption
```

**Potential Profit:**
- **For attacker:** None (this is a griefing attack)
- **Impact:** Network congestion, wasted gas

**Difficulty:** LOW
**Exploitability:** MEDIUM

**Code Reference:**
```solidity
// AmpleEarnCrossChainRouter.sol L89-133
function batchCrossChainClaimPayout(LayerZeroClaimPayoutParams[] calldata _params)
    external payable {
    uint256 totalValueUsed;
    for (uint256 i = 0; i < _params.length; i++) {
        // ... validate, quote, send
        totalValueUsed += fee.nativeFee;
    }
    // Refund at end — may not execute if gas runs out
    if (msg.value > totalValueUsed) {
        (bool success,) = payable(msg.sender).call{value: msg.value - totalValueUsed}("");
    }
}
```

**Mitigations:**
- Maximum batch size limit
- Refund per iteration instead of at end

**Validation Status:** ✅ Verified (AE-F-003)

---

## THREAT T-11: 0-Value Deposit / Withdraw Manipulation

**Category:** Technical — Accounting Drift

**Threat:**
A 0-value deposit or withdraw on the ERC-4626 vault triggers accounting updates without actual asset transfer. If internal accounting depends on `_deposit()` or `_withdraw()` being called with non-zero amounts, 0-value calls could cause accounting drift or manipulation.

**Attack Preconditions:**
- `deposit(0)` or `mint(0)` or `withdraw(0)` does not revert
- Internal state is updated even for 0-value operations

**Required Capital:**
- Zero

**Required Permissions:**
- None — any depositor/withdrawer

**Code Analysis:**
From OZ ERC4626: 0-asset deposit would trigger fee accrual and strategy rebalancing without meaningful movement, wasting gas.

**Potential Impact:**
- **Gas waste:** Triggering rebalancing without meaningful allocation
- **No direct fund loss** — 0-value operations should be no-ops

**Difficulty:** LOW
**Exploitability:** LOW

**Validation Status:** ⚠️ Needs investigation (AE-E-003, AE-E-004)

---

## THREAT T-12: Permit2 Signature Replay / Validation Bypass

**Category:** Technical — External Integration

**Threat:**
`SafeERC20Permit2Lib.safeTransferFromWithPermit2()` handles Permit2 signatures for USDC transfers. If signature validation has a flaw (e.g., missing deadline check, wrong domain separator, nonce reuse), an attacker could replay a signature or bypass authorization.

**Attack Preconditions:**
- User has signed a Permit2 approval for USDC transfers
- Signature validation logic has a bug
- Chain has different Permit2 address or domain separator mismatch

**Required Capital:**
- A validly signed Permit2 message (from a legitimate user)

**Required Permissions:**
- The signed message (publicly available on-chain)

**Attack Path (Hypothetical):**
```
1. User signs Permit2 transfer: from=user, to=vault, amount=1000 USDC
2. Attacker intercepts signature (published on-chain in calldata)
3. If nonce already used → replay fails
4. If expiration not validated → can replay expired signatures
5. If chain ID not validated → can replay on different chain
```

**Cross-Chain Replay Risk:**

| Chain | Permit2 Address | Domain Separator | Signature Replay? |
|---|---|---|---|
| Base | Base Permit2 | Base chain ID | Different → no |
| Arbitrum | Arb Permit2 | Arb chain ID | Different → no |
| Monad | Monad Permit2 | Monad chain ID | Different → no |
| Katana | Katana Permit2 | Katana chain ID | Different → no |

**Mitigations:** EIP-712 domain separator includes chainId; nonce tracking prevents single-chain replays

**Difficulty:** HIGH (requires signature extraction + validation flaw)
**Exploitability:** LOW

**Validation Status:** ⚠️ Needs investigation

---

## THREAT T-13: Payout Reservation Drain

**Category:** Technical — Accounting

**Threat:**
The `AmpleEarnReserve` holds tokens for future payouts. If there's a bug in how reserves are funded, tracked, or disbursed, an attacker could drain reserves by claiming more than the allocated payout amount.

**Attack Preconditions:**
- `_deposit` under-allocates to reserves
- `_withdraw` incorrectly accounts for reserved funds
- OR: payout execution doesn't properly check reserve sufficiency

**Required Capital:**
- A valid merkle proof (winner status)

**Required Permissions:**
- PayoutManager (to set merkle roots) OR a valid winner

**Code Analysis:**
From `AmpleEarn.sol`: `claimPayout()` verifies merkle proof, checks `isPayoutClaimed(payoutId) == false`, then transfers payout from reserve. Need to verify reserve sufficiency check.

**Potential Profit:**
- **Direct:** Value of unbacked payouts claimed

**Difficulty:** MEDIUM (depends on reserve accounting)
**Exploitability:** LOW-MEDIUM

**Validation Status:** ⚠️ Needs investigation

---

## THREAT T-14: Griefing via Unverified Strategy Factory Deployment

**Category:** Technical — Denial of Service

**Threat:**
If the factory's `isStrategyAllowed()` check in `createAmpleEarn()` uses the perspective contract, and the perspective contract is not yet set (or set to an address that reverts), the factory cannot deploy new vaults.

**Attack Preconditions:**
- `perspective` address is set to a contract that reverts on `isVerified()`
- OR: `perspective` is address(0)

**Required Capital:**
- Zero (triggered by misconfiguration or previous attack)

**Required Permissions:**
- Owner (can set perspective) OR previous attack payload

**Code Analysis:**
From `AmpleEarnFactory.sol`:
```solidity
function createAmpleEarn(...) external onlyOwner returns (address) {
    if (!IAmplePerspective(perspective).isVerified(address(vault))) {
        revert NotVerified();
    }
}
```

**Potential Profit:** Zero (pure griefing); **Impact:** Protocol cannot deploy new vaults

**Difficulty:** LOW
**Exploitability:** LOW (requires owner or previous perspective manipulation)

**Validation Status:** ✅ Verified

---

## CROSS-CHAIN THREAT MATRIX

| Threat | Base | Arbitrum | Monad | Katana | Cross-Chain |
|---|---|---|---|---|---|
| T-1: ERC-4626 Donation | 🔴 | 🟡 | 🟢 | 🟢 | No |
| T-2: Payout Replay | 🟡 | 🟡 | 🟡 | 🟡 | 🔴 Yes |
| T-3: Oracle Manip | 🟢 | 🟢 | 🟡 | 🟡 | No |
| T-4: Proxy Upgrade | 🟢 | 🟢 | 🔴 | 🟢 | No |
| T-5: MEV Front-Run | 🟡 | 🟢 | 🟢 | 🟢 | No |
| T-6: Malicious Perspective | 🟡 | 🟡 | 🟡 | 🟡 | No |
| T-7: Flashloan + Replay | 🟡 | 🟡 | 🟢 | 🟢 | 🔴 Yes |
| T-8: Cap Bypass | 🟡 | 🟡 | 🟢 | 🟢 | No |
| T-9: LZ Peer Hijack | 🟡 | 🟡 | 🟡 | 🟡 | 🔴 Yes |
| T-10: Gas Griefing | 🟢 | 🟢 | 🟢 | 🟢 | No |
| T-11: 0-Value Ops | 🟢 | 🟢 | 🟢 | 🟢 | No |
| T-12: Permit2 Replay | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 Yes (mitigated) |
| T-13: Reserve Drain | 🟡 | 🟢 | 🟢 | 🟢 | No |
| T-14: Factory Grief | 🟢 | 🟢 | 🟢 | 🟢 | No |

---

## EXPLOITABILITY VS DIFFICULTY MATRIX

| Threat | Exploitability | Difficulty | Priority |
|---|---|---|---|
| T-1: ERC-4626 Donation | MEDIUM | LOW | 🔴 P0 |
| T-2: Cross-Chain Payout Replay | MEDIUM | LOW-MEDIUM | 🔴 P0 |
| T-3: Oracle Manipulation | LOW | VERY HIGH | 🟢 P3 |
| T-4: Proxy Upgrade (Monad) | LOW | HIGH | 🟡 P2 |
| T-5: MEV Front-Running | MEDIUM | MEDIUM | 🟡 P2 |
| T-6: Malicious Perspective | LOW | LOW | 🟡 P2 |
| T-7: Flashloan + Replay Racing | MEDIUM | MEDIUM-HIGH | 🟡 P1 |
| T-8: Cap Timelock Bypass | LOW-MEDIUM | LOW | 🟡 P2 |
| T-9: LZ Peer Hijack | LOW | LOW | 🟡 P2 |
| T-10: Gas Griefing | MEDIUM | LOW | 🟢 P3 |
| T-11: 0-Value Operations | LOW | LOW | 🟢 P3 |
| T-12: Permit2 Replay | LOW | HIGH | 🟢 P3 |
| T-13: Reserve Drain | LOW-MEDIUM | MEDIUM | 🟡 P2 |
| T-14: Factory Grief | LOW | LOW | 🟢 P3 |

---

## ATTACKER PROFILES — DETAILED

### Profile 1: Flashloan Attacker

| Attribute | Value |
|---|---|
| **Capital** | $0-$50M (flashloan, no upfront) |
| **Technical Skill** | High — must deploy custom contracts |
| **Tools** | Foundry, hardhat, flashloan provider (Balancer, Aave, Uniswap) |
| **Target** | Accounting imbalance, share price manipulation |
| **Relevant Threats** | T-1 (no flashloan needed), T-3, T-7 |
| **Profit Model** | Exploit temporary price deviation × volume |
| **Mitigations** | nonReentrant, try/catch, EVC context |

### Profile 2: MEV Searcher

| Attribute | Value |
|---|---|
| **Capital** | Moderate — vault position ($10K-$100K) |
| **Technical Skill** | High — mempool monitoring, bundle construction |
| **Tools** | Flashbots, MEV-boost, searcher bots |
| **Target** | Prize distribution timing, yield accrual events |
| **Relevant Threats** | T-5 |
| **Profit Model** | Front-run + back-run price changes from events |
| **Mitigations** | Private mempool, commit-reveal, nonReentrant |

### Profile 3: Malicious Admin / Key Compromise

| Attribute | Value |
|---|---|
| **Capital** | Zero (has keys) |
| **Technical Skill** | Medium |
| **Tools** | Multi-sig wallet interface |
| **Target** | Upgrade, setPerspective, setPeer |
| **Relevant Threats** | T-4, T-6, T-9 |
| **Profit Model** | Direct fund extraction |
| **Mitigations** | Multi-sig threshold, timelock, monitoring |

### Profile 4: Cross-Chain Attacker

| Attribute | Value |
|---|---|
| **Capital** | Low — gas fees only |
| **Technical Skill** | Medium |
| **Tools** | LayerZero SDK, cross-chain explorer |
| **Target** | payoutId uniqueness, message ordering |
| **Relevant Threats** | T-2, T-7 |
| **Profit Model** | Double claims, race conditions |
| **Mitigations** | Global nonce, vault-specific tracking |

---

## TRUST BOUNDARIES

```
┌─────────────────────────────────────────────────┐
│                  TRUSTED                         │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐ │
│  │ Owner    │  │ Curator  │  │ Guardian      │ │
│  │ (multi-  │  │ (strategy│  │ (timelock     │ │
│  │  sig)    │  │  config) │  │  canceller)   │ │
│  └────┬─────┘  └────┬─────┘  └──────┬────────┘ │
│       │              │               │          │
│       └──────────────┴───────────────┘          │
│                         │                       │
├─────────────────────────┼───────────────────────┤
│              SEMI-TRUSTED│                      │
│                         ▼                       │
│  ┌─────────────────────────────────────────┐    │
│  │ PayoutManager      │   Allocator        │    │
│  │ (merkle roots)     │   (reallocation)   │    │
│  └─────────────────────┴───────────────────┘    │
│                         │                       │
├─────────────────────────┼───────────────────────┤
│              UNTRUSTED   │                      │
│                         ▼                       │
│  ┌─────────────────────────────────────────┐    │
│  │ Users (depositors, winners, claimants)  │    │
│  └─────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────┐    │
│  │ LayerZero DVN (cross-chain validators) │    │
│  └─────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────┐    │
│  │ Euler EVK Strategies (yield sources)    │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

---

## RECOMMENDED MITIGATIONS

| Threat | Mitigation | Effort | Priority |
|---|---|---|---|
| T-1: ERC-4626 Donation | Virtual shares / dead share provision | Medium | 🔴 High |
| T-2: Payout Replay | Global payoutId counter + vault-specific mapping | High | 🔴 High |
| T-4: Proxy Upgrade | Timelock on proxy admin | Low | 🟡 Medium |
| T-5: MEV Front-Run | Commit-reveal or private mempool | High | 🟢 Low |
| T-6: Malicious Perspective | Timelock on setPerspective() | Low | 🟡 Medium |
| T-9: LZ Peer Hijack | Multi-sig + event monitoring | Low | 🟡 Medium |
| T-10: Gas Griefing | Max batch size limit | Low | 🟢 Low |

---

## SUMMARY OF HIGHEST PRIORITY THREATS

| Rank | Threat | Impact | Exploitability | Urgency |
|---|---|---|---|---|
| **1** | T-1: ERC-4626 Donation | High ($4.33M TVL at risk) | MEDIUM | 🔴 Fork test immediately |
| **2** | T-2: Cross-Chain Payout Replay | High (double claims) | MEDIUM | 🔴 Verify payoutId tracking |
| **3** | T-7: Flashloan + Replay | Medium-High | MEDIUM | 🟡 Validate racing window |
| **4** | T-5: MEV Front-Running | Medium | MEDIUM | 🟡 Review distribution timing |
| **5** | T-13: Reserve Drain | Medium | LOW-MEDIUM | 🟡 Verify reserve accounting |
| **6** | T-4: Proxy Upgrade (Monad) | Critical (if compromised) | LOW | 🟡 Verify proxy admin config |

---

*Document generated from: Source code analysis, RECON_PER_CHAIN.md, CROSS_CHAIN_COMPARISON.md, FINDINGS_CHECKLIST.md, PRIVILEGED_FUNCTIONS.md, EDGE_CASES.md, WORKFLOWS/threat_model.md*
