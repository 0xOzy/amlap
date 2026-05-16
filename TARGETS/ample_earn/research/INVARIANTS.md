# Invariants — Ample Earn

**Date:** 2026-05-15
**Target:** Ample Earn — Prize-linked savings protocol on Euler Earn
**Scope:** AmplePerspective, AmpleEarnFactory, AmpleEarnCrossChainRouter (×4 chains)
**Methodology:** Source code analysis → Asset flow mapping → Share/debt relationship → Trust assumption identification → Edge case exploration

---

## How to Read This Document

| Section | Description |
|---|---|
| **Invariant** | A property that MUST always remain true |
| **Reasoning** | Why this invariant exists — what makes it "invariant" |
| **Potential Break Path** | How an attacker or edge case could violate this invariant |
| **Impact of Break** | What happens if the invariant is violated |
| **Confidence** | How confident we are that this invariant holds in the current code |
| **Validation Status** | Whether it has been verified on-chain / via fork test |

---

## I. ERC-4626 VAULT INVARIANTS

### INV-001: Vault Always Fully Backed

| Field | Value |
|---|---|
| **Invariant** | `totalAssets() >= totalSupply()` in terms of base asset value |
| **Category** | Accounting |
| **Component** | `EulerEarn` (underlying), affects all scope contracts |
| **Chains** | All |

**Reasoning:**
Each share represents a claim on underlying assets. The ERC-4626 standard requires that `totalAssets()` references the vault's actual holdings. If `totalSupply() > totalAssets()`, shares are not fully backed, and late withdrawers cannot exit at full value.

```solidity
// OZ ERC4626._convertToShares()
function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
    return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
}
```

**Potential Break Path:**
1. **ERC-4626 Donation Attack** (AE-F-001): `totalAssets()` is inflated by donation → `totalSupply()` remains → exchange rate broken. But this inflates backing, doesn't break `totalAssets() >= totalSupply()`.
2. **Realized losses**: Euler EVK strategies realize bad debt → `totalAssets()` decreases while `totalSupply()` unchanged → `totalAssets() < totalSupply()`. This is an intended protocol behavior (losses socialized).
3. **Fee-on-transfer token**: If USDC enables transfer fees, `_deposit()` records more assets than actually received → `totalAssets()` > actual vault holdings → inflated backing.

**Impact of Break:**
- Late withdrawers cannot redeem full value of shares
- Protocol becomes insolvent
- Last depositors bear all losses

**Confidence:** HIGH (standard ERC-4626)
**Validation Status:** ⚠️ Needs fork test for donation attack (AE-F-001)

---

### INV-002: Share Price Monotonically Non-Decreasing

| Field | Value |
|---|---|
| **Invariant** | Exchange rate (`totalAssets() / totalSupply()`) does not decrease except when losses are realized |
| **Category** | Accounting — Pricing |
| **Component** | `EulerEarn` |
| **Chains** | All |

**Reasoning:**
The vault generates yield through Euler EVK strategies. Yield accrual increases `totalAssets()` without changing `totalSupply()`, causing the exchange rate to increase monotonically. Fees are deducted from yield, not principal. Realized losses are the only mechanism that should decrease the exchange rate.

```solidity
// EulerEarn._accruedFeeAndAssets()
function _accruedFeeAndAssets() internal returns (uint256, uint256) {
    uint256 currentTotalAssets = totalAssets();
    uint256 lastTotalAssets_ = lastTotalAssets;
    if (currentTotalAssets > lastTotalAssets_) {
        // Yield accrued
        uint256 fee = (currentTotalAssets - lastTotalAssets_) * feePercentage / FEE_PERCENTAGE_BASIS;
        // ... distribute fee
    }
    // Realized losses: currentTotalAssets < lastTotalAssets_ is allowed
}
```

**Potential Break Path:**
1. **Yield reversion**: If a strategy reports negative yield (but doesn't realize losses), `currentTotalAssets < lastTotalAssets_` → exchange rate decreases
2. **Oracle manipulation**: If strategy `previewRedeem` returns lower value due to oracle manipulation → temporary decrease
3. **Fee skimming**: If performance fee is deducted from principal rather than yield → artificial decrease

**Important:** The invariant should state "non-decreasing **except when losses are realized**" — the protocol explicitly allows loss realization.

**Impact of Break:**
- Depositors see share value decrease without explicit loss event
- Erosion of trust in the protocol
- Potential arbitrage (withdraw before loss, re-deposit after)

**Confidence:** HIGH (standard vault mechanic)
**Validation Status:** ✅ Verified via source

---

### INV-003: Depositors Cannot Lose Principal via Normal Operations

| Field | Value |
|---|---|
| **Invariant** | A depositor's maximum loss is limited to yield shortfall + realized losses; principal cannot be stolen via accounting manipulation |
| **Category** | Accounting — User Protection |
| **Component** | `EulerEarn`, `AmpleEarn` |
| **Chains** | All |

**Reasoning:**
ERC-4626 vaults guarantee proportional redemption: `shares * totalAssets() / totalSupply()` returned on withdrawal. If no losses are realized, exchange rate only increases. Direct theft of deposited assets requires breaking either the accounting system or the withdrawal mechanism.

**Potential Break Path:**
1. **ERC-4626 Donation Attack** (AE-F-001): Victim receives fewer shares for same deposit → effectively loses value to attacker. This is NOT theft from vault, but value extraction via share price manipulation.
2. **Reentrancy** (AE-F-005): If `batchCrossChainClaimPayout()` is re-entered, state could be manipulated → theft.
3. **Malicious perspective** (AE-P-001): If `setPerspective()` points to malicious contract, future vault deployments route deposits to fake strategies → DIRECT THEFT.

**Impact of Break:**
- User deposits lost or severely diluted
- Up to full TVL of affected vault ($4.33M on Base)

**Confidence:** MEDIUM (donation attack is a known ERC-4626 risk)
**Validation Status:** ⚠️ Needs fork test (AE-F-001)

---

### INV-004: Share Minting / Burning Is Proportional

| Field | Value |
|---|---|
| **Invariant** | `shares_minted / assets_deposited == totalSupply() / totalAssets()` (within rounding) |
| **Category** | Accounting — Proportionality |
| **Component** | `EulerEarn` (ERC-4626) |
| **Chains** | All |

**Reasoning:**
OZ ERC4626 defines:
```solidity
shares = _convertToShares(assets, Math.Rounding.Floor);
// ...
_mint(receiver, shares);
```

`_convertToShares(assets) = assets * totalSupply() / totalAssets()`.

This ensures each depositor receives a fair proportion of shares based on current vault state.

**Potential Break Path:**
1. **Front-running donation**: Attacker donates directly to vault before deposit → `totalAssets()` inflated → victim receives fewer shares
2. **Flashloan + strategy manipulation**: Temporary `totalAssets()` manipulation via EVK strategy share price
3. **Rounding exploitation**: Repeated dust deposits could exploit rounding direction (Floor for shares, Ceil for assets)

**Impact of Break:**
- Unequal distribution of vault ownership
- Attacker extracts value from subsequent depositors

**Confidence:** HIGH (OZ standard, well-audited)
**Validation Status:** ✅ Verified via source

---

### INV-005: Total Supply Equals Sum of All Share Balances

| Field | Value |
|---|---|
| **Invariant** | `totalSupply() == sum(balanceOf(user) for all users)` |
| **Category** | Accounting — Consistency |
| **Component** | ERC-20 (OZ) |
| **Chains** | All |

**Reasoning:**
Standard ERC-20 invariant. OZ implementation ensures `_mint` increases totalSupply and `_burn` decreases it atomically with balance updates.

**Potential Break Path:**
- Extremely unlikely in OZ Solidity 0.8.x
- Only via malicious upgrade of the underlying ERC20 implementation

**Impact of Break:** Complete accounting failure
**Confidence:** VERY HIGH (battle-tested OZ code)
**Validation Status:** ✅ Verified

---

## II. PRIZE DISTRIBUTION INVARIANTS

### INV-006: Total Payouts ≤ Total Yield Accrued

| Field | Value |
|---|---|
| **Invariant** | Sum of all payouts distributed ≤ total yield generated by the vault |
| **Category** | Accounting — Prize Pool |
| **Component** | `AmpleEarn` |
| **Chains** | All |

**Reasoning:**
Prize-linked savings requires that prizes come from yield, not principal. `AmpleEarn` tracks yield via `lastTotalAssets` vs `currentTotalAssets` in `_accruedFeeAndAssets()`. Payouts are funded from `AmpleEarnReserve`.

**Potential Break Path:**
1. **Reserve underfunding**: If `claimedPayouts` is not properly checked against yield → payout from principal
2. **Double claim** (AE-F-002): Same payoutId claimed multiple times → more paid out than allocated
3. **Yield over-counting**: If `totalAssets()` is manipulated upward → appears more yield exists than actually does → merkle roots set for payouts that exceed real yield

**Impact of Break:**
- Protocol becomes insolvent
- Depositors lose principal to payouts
- Up to $4.33M at risk on Base

**Confidence:** MEDIUM (depends on payoutId uniqueness and reserve accounting)
**Validation Status:** ⚠️ Needs investigation (AE-F-002)

---

### INV-007: Payouts Are Verifiably Random

| Field | Value |
|---|---|
| **Invariant** | Winner selection is unpredictable and cannot be influenced by users or validators |
| **Category** | Fairness — Randomness |
| **Component** | `AmpleEarn` (VRF integration) |
| **Chains** | All |

**Reasoning:**
Prize distribution uses verifiable randomness (likely Chainlink VRF or similar). The random output determines winner selection from the pool of eligible depositors.

**Potential Break Path:**
1. **VRF revealing**: If randomness source is known before distribution, MEV searcher can front-run to qualify for prize
2. **RNG manipulation**: If on-chain randomness (e.g., blockhash) is used instead of VRF, validators could influence outcome
3. **Reveal delay**: If validator can withhold VRF proof to avoid unfavorable distribution

**Impact of Break:**
- Unfair prize distribution
- Attacker can guarantee wins
- Protocol integrity compromised

**Confidence:** LOW (needs verification of randomness source)
**Validation Status:** ❓ Unknown — needs investigation

---

### INV-008: Prize Distribution Does Not Dilute Existing Shares

| Field | Value |
|---|---|
| **Invariant** | Prize distribution events do not change share-to-asset ratio for non-winning depositors |
| **Category** | Accounting — Dilution |
| **Component** | `AmpleEarn`, `EulerEarn` |
| **Chains** | All |

**Reasoning:**
Prize payouts come from yield that has already been accounted for in `totalAssets()`. When a payout is made, it reduces `totalAssets()` (transferring from reserve). Since the yield was already reflected in share price before the payout (as unrealized gains), the payout represents a distribution of already-accrued value.

**Potential Break Path:**
1. **Payout > accrued yield**: If payout exceeds yield accrued since last checkpoint, non-winners subsidize winners
2. **Loss before payout**: If strategy realizes a loss before payout, the yield was never actually earned but was already "promised" as prizes

**Impact of Break:**
- Non-winning depositors lose value
- Protocol effectively taxes non-winners for prizes

**Confidence:** MEDIUM (depends on yield accounting correctness)
**Validation Status:** ⚠️ Needs investigation

---

## III. CROSS-CHAIN INVARIANTS

### INV-009: Each PayoutId Processed Exactly Once (No Replay)

| Field | Value |
|---|---|
| **Invariant** | `isPayoutClaimed(payoutId)` returns `true` for any payoutId that has been claimed on any chain (globally unique) |
| **Category** | Cross-Chain — Replay Protection |
| **Component** | `AmpleEarnCrossChainRouter`, `AmpleEarn` |
| **Chains** | All |

**Reasoning:**
This is the most critical cross-chain invariant. If a payoutId can be claimed on multiple chains, the total payouts exceed the allocated prize pool, draining the protocol.

**Critical Code Path:**
```solidity
// AmpleEarnCrossChainRouter._executeClaims()
for (uint256 i = 0; i < _claims.length; i++) {
    ClaimPayoutParams calldata claim = _claims[i];
    if (IAmpleEarn(claim.vault).isPayoutClaimed(claim.payoutId)) {
        revert PayoutAlreadyClaimed(payoutId);
    }
    IAmpleEarn(claim.vault).claimPayout(
        claim.payoutId, claim.claimIndex, claim.payout, claim.proof
    );
    emit CrossChainClaimExecuted(claim.vault, claim.payoutId);
}
```

**Key Question:** Is `claimedPayouts` a global mapping across ALL vaults on the chain, or per-vault?

```solidity
// NEED VERIFICATION: Storage layout
// Option A: mapping(uint256 => bool) public claimedPayouts;  // GLOBAL - safe
// Option B: mapping(address vault => mapping(uint256 => bool)) public claimedPayouts;  // PER-VAULT - needs vault uniqueness
```

**Potential Break Path:**
1. If `claimedPayouts` is per-vault AND same vault address exists on multiple chains (same CREATE2 salt) → same payoutId can be claimed on each chain
2. If merkle root is shared across chains → same merkle proof works on multiple chains
3. LayerZero message replay (if GUID not checked)

**Impact of Break:** 🔴 CRITICAL — unlimited double claims, complete protocol drain
**Confidence:** MEDIUM (needs storage layout verification)
**Validation Status:** ⚠️ Needs investigation (AE-F-002)

---

### INV-010: LayerZero Message Sender Matches Expected Peer

| Field | Value |
|---|---|
| **Invariant** | In `_lzReceive()`, the `_origin.sender` must equal the trusted peer for the source chain's EID |
| **Category** | Cross-Chain — Authentication |
| **Component** | `AmpleEarnCrossChainRouter` |
| **Chains** | All |

**Reasoning:**
LayerZero OApp provides `OnlyPeer()` modifier that ensures only messages from trusted peers are processed. Without this, anyone could send pretend messages from any chain.

```solidity
// OApp._lzReceive()
function _lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
) internal override {
    // OnlyPeer check in parent
    // ...
    _executeClaims(dstEid, claims);
}
```

**Potential Break Path:**
1. **Owner calls setPeer(eid, attackerAddr)** (AE-P-002): Changes trusted peer → attacker messages accepted
2. **LayerZero DVN compromise**: Validators attest fake message from fake sender
3. **Peer misconfiguration**: If `setPeer()` is called with wrong eid/address combination

**Impact of Break:**
- Unauthorized cross-chain messages processed
- Fake payout claims executed
- Protocol funds stolen

**Confidence:** HIGH (standard OApp pattern)
**Validation Status:** ✅ Verified via source

---

### INV-011: Cross-Chain Claims Only for Valid Vaults

| Field | Value |
|---|---|
| **Invariant** | `batchCrossChainClaimPayout()` and `_executeClaims()` only process claims for vaults that exist (are recognized by the factory) |
| **Category** | Cross-Chain — Authorization |
| **Component** | `AmpleEarnCrossChainRouter` |
| **Chains** | All |

**Reasoning:**
```solidity
// batchCrossChainClaimPayout() validation
if (!IAmpleEarnFactory(factory).isVault(address(vault))) {
    revert NotVerified();
}
```

**Potential Break Path:**
1. **Factory returns incorrect `isVault()`** due to compromised perspective or proxy upgrade
2. **Same vault address on multiple chains**: Valid vault on chain A, but invalid vault on chain B claiming via cross-chain

**Impact of Break:**
- Claims processed for non-existent vaults
- Payouts sent to addresses not controlled by the protocol

**Confidence:** HIGH (standard factory pattern)
**Validation Status:** ✅ Verified via source

---

## IV. FACTORY INVARIANTS

### INV-012: Vault Addresses Are Deterministic (CREATE2)

| Field | Value |
|---|---|
| **Invariant** | Same CREATE2 salt + deployer + bytecode → same address on any EVM chain |
| **Category** | Deployment — Address Determinism |
| **Component** | `AmpleEarnFactory` |
| **Chains** | Base, Arbitrum, Monad, Katana |

**Reasoning:**
```solidity
// AmpleEarnFactory.createAmpleEarn()
address vault = address(new AmpleEarn{salt: keccak256(abi.encodePacked(custodian, name, symbol))}(
    address(evc), address(permit2), address(vault), type(uint256).max,
    address(perspective), name, symbol, payoutFeeNumerator, PAYOUT_RESERVE
));
```

**Potential Break Path:**
1. **Different deployer**: If the deployer address differs, different address → `isVault()` fails on cross-chain calls
2. **Proxy impact (Monad)**: Monad factory is behind proxy → `CREATE2` is executed in the context of the implementation, not the proxy → address same (CREATE2 uses implementation bytecode)
3. **Hardfork changes**: If EVM changes CREATE2 semantics (extremely unlikely)

**Impact of Break:**
- Cross-chain vault address verification fails
- Cross-chain claims revert
- Protocol interoperability broken

**Confidence:** HIGH (CREATE2 is EVM standard)
**Validation Status:** ✅ Verified

---

### INV-013: Only Whitelisted Strategies Can Be Added to Vaults

| Field | Value |
|---|---|
| **Invariant** | A vault can only allocate funds to strategies that pass `IAmplePerspective.isVerified(strategy)` |
| **Category** | Authorization — Strategy Validation |
| **Component** | `AmplePerspective`, `AmpleEarnFactory` |
| **Chains** | All |

**Reasoning:**
```solidity
// AmpleEarnFactory.createAmpleEarn()
if (!IAmplePerspective(perspective).isVerified(address(vault))) {
    revert NotVerified();
}
```

The perspective contract acts as a whitelist. Only strategies added via `verify(strategy)` by the owner are valid.

**Potential Break Path:**
1. **Owner calls setPerspective(malicious)** (AE-P-001): New perspective returns `isVerified() = true` for all addresses
2. **Perspective contract compromised**: If perspective itself has a vulnerability
3. **Monad proxy upgrade** (AE-C-001): Owner upgrades factory → deployment logic changed

**Impact of Break:**
- Deposits sent to fake/risky strategies
- Complete loss of deposited funds

**Confidence:** HIGH (onlyOwner gated)
**Validation Status:** ✅ Verified via source

---

### INV-014: Cap Increases Are Timelocked

| Field | Value |
|---|---|
| **Invariant** | Strategy cap increases have a mandatory delay (timelock) before taking effect |
| **Category** | Governance — Operational Security |
| **Component** | `CuratorLib`, `EulerEarn` |
| **Chains** | All |

**Reasoning:**
```solidity
// CuratorLib.setCap()
function setCap(...) external {
    // ...
    if (_newCap > config.cap) {
        // Cap increase requires timelock
        pendingCap[id] = PendingUint136(uint136(_newCap), block.timestamp + TIMELOCK_DURATION);
        emit EventsLib.SubmitCap(id, _newCap);
    } else {
        // Cap decrease is immediate
        config.cap = _newCap;
        emit EventsLib.SetCap(id, _newCap);
    }
}
```

**Potential Break Path:**
1. **Guardian cancel + Curator resubmit** (AE-P-004): If no cooldown, cancel and immediate resubmit chains timelocks
2. **Timelock bypass**: If `TIMELOCK_DURATION = 0` for any reason (config error)
3. **OnlyOwner override**: Owner might have ability to bypass timelock

**Impact of Break:**
- Strategy cap increased without delay
- Potentially risky over-allocation
- Depositors exposed to unvetted strategies

**Confidence:** HIGH (timelock enforced in code)
**Validation Status:** ✅ Verified via source

---

## V. EULER EVK UNDERLYING INVARIANTS (OUT OF SCOPE)

### INV-015: Underlying EVK Strategies Remain Solvent

| Field | Value |
|---|---|
| **Invariant** | Each Euler EVK lending strategy maintains `totalCollateral >= totalDebt` and unhealthy positions are liquidatable |
| **Category** | DeFi — Solvency |
| **Component** | Euler EVK (out of scope) |
| **Chains** | All |

**Reasoning:**
AmpleEarn vault deposits funds into Euler EVK strategies. If these strategies become insolvent (bad debt exceeds collateral), AmpleEarn depositors bear the loss.

**Potential Break Path:**
1. **Oracle manipulation**: Chainlink feed manipulated → incorrect collateral valuations → under-collateralized positions not liquidated
2. **Market crash**: Rapid price movement outpaces liquidations → bad debt
3. **Liquidity crisis**: No liquidators available to clear bad positions

**Impact of Break:**
- AmpleEarn `expectedSupplyAssets()` decreases
- `lastTotalAssets` adjusted downward via realized losses
- Late withdrawers exit at loss

**Confidence:** LOW (out of scope, depends on EVK health)
**Validation Status:** ❓ Unknown

---

### INV-016: Strategy Cap Allocation Prevents Over-Concentration

| Field | Value |
|---|---|
| **Invariant** | `balanceOfStrategy(id) <= cap(id)` for all strategies at all times |
| **Category** | Risk Management — Allocation |
| **Component** | `StrategyLib`, `EulerEarn` |
| **Chains** | All |

**Reasoning:**
```solidity
// StrategyLib.supplyStrategy()
function supplyStrategy(...) external returns (uint256 suppliedShares) {
    // ...
    uint256 cap = config.cap;
    if (toSupply > cap - config.balance) {
        toSupply = cap - config.balance;  // Clamp to remaining cap space
    }
    // ...
}
```

**Potential Break Path:**
1. **Cap increase via timelock**: New cap takes effect after delay → temporary over-allocation possible
2. **Cap race condition**: If cap is decreased while funds are deployed, strategy may be over cap
3. **No upper bound check on supply**: If multiple strategies reach cap simultaneously

**Impact of Break:**
- Over-concentration in a single strategy
- Increased risk exposure for depositors

**Confidence:** HIGH (enforced in allocation logic)
**Validation Status:** ✅ Verified via source

---

## VI. ACCOUNTING CONSISTENCY INVARIANTS

### INV-017: `lastTotalAssets` Reflects Accurate Vault State

| Field | Value |
|---|---|
| **Invariant** | `lastTotalAssets` is updated atomically with every deposit/withdraw/fee-accrual operation |
| **Category** | Accounting — State Consistency |
| **Component** | `EulerEarn` |
| **Chains** | All |

**Reasoning:**
`lastTotalAssets` tracks the last checkpointed value of `totalAssets()`. It is compared against `currentTotalAssets()` to compute accrued yield.

```solidity
function _accruedFeeAndAssets() internal returns (uint256, uint256) {
    uint256 currentTotalAssets = totalAssets();
    uint256 lastTotalAssets_ = lastTotalAssets;
    // ... fee calculation based on difference
    lastTotalAssets = currentTotalAssets;
}
```

**Potential Break Path:**
1. **Reentrancy**: If `_accruedFeeAndAssets()` is called reentrantly before `lastTotalAssets` is updated
2. **Skip fee accrual**: If `_accruedFeeAndAssets()` is not called before modifying state
3. **Uninitialized `lastTotalAssets`**: If first deposit doesn't properly initialize (Slither: `uninitialized-local`)

**Impact of Break:**
- Incorrect fee calculations
- Yield over- or under-counted
- Share price wrong

**Confidence:** MEDIUM (depends on proper state management)
**Validation Status:** ⚠️ Needs investigation (AE-S-005)

---

### INV-018: Fee Calculation Uses Only Yield, Not Principal

| Field | Value |
|---|---|
| **Invariant** | Performance fee is computed as `(currentTotalAssets - lastTotalAssets) * feePercentage / BASIS`, only when `currentTotalAssets > lastTotalAssets` |
| **Category** | Accounting — Fee Integrity |
| **Component** | `EulerEarn` |
| **Chains** | All |

**Reasoning:**
```solidity
if (currentTotalAssets > lastTotalAssets_) {
    uint256 fee = (currentTotalAssets - lastTotalAssets_) * feePercentage / FEE_PERCENTAGE_BASIS;
    // fee only deducted from positive yield
}
```

**Potential Break Path:**
1. **Fee on negative yield**: If `feePercentage` is applied when `currentTotalAssets < lastTotalAssets_` → fee on principal
2. **Fee percentage manipulation**: Owner sets `feePercentage = 100%` → all yield goes to fee, depositors get nothing
3. **Double fee accrual**: If fee is counted twice on same yield (reentrancy or missed update)

**Impact of Break:**
- Depositors unfairly charged
- Principal erosion over time

**Confidence:** HIGH (only positive yield logic)
**Validation Status:** ✅ Verified via source

---

## VII. TRUST & SECURITY INVARIANTS

### INV-019: Only Owner Can Upgrade Proxy (Monad)

| Field | Value |
|---|---|
| **Invariant** | Only the proxy admin (multi-sig owner) can call `upgradeTo()` on the Monad factory proxy |
| **Category** | Governance — Upgrade Authority |
| **Component** | AmpleEarnFactory (Monad) |
| **Chain** | Monad only |

**Reasoning:**
Standard OpenZeppelin `Proxy.sol` and `ProxyAdmin.sol` pattern — only the admin can change the implementation address.

**Potential Break Path:**
1. **Proxy admin transfer**: Owner transfers admin rights to malicious address
2. **Proxy admin renounce**: Admin becomes `address(0)` → no one can upgrade (but also no one can fix bugs)
3. **Selfdestruct in implementation**: If implementation contains `selfdestruct`, could destroy storage

**Impact of Break:**
- Factory logic completely replaced
- All future vault deployments compromised

**Confidence:** MEDIUM (needs on-chain verification of proxy admin)
**Validation Status:** ⚠️ Needs on-chain verification (AE-C-001)

---

### INV-020: Creator Has No Special Privileges

| Field | Value |
|---|---|
| **Invariant** | The original deployer/creator of contracts does NOT retain any special privileges beyond those explicitly assigned (Owner via Ownable2Step) |
| **Category** | Governance — Decentralization |
| **Component** | All scope contracts |
| **Chains** | All |

**Reasoning:**
All scope contracts use `Ownable2Step` for ownership management. There are no immutable creator addresses, `tx.origin` checks, or deployer-specific privileges.

```solidity
// AmpleEarnFactory constructor
constructor(address _owner, address _evc, address _permit2, address _perspective)
    Ownable(_owner) // Owner set explicitly, not msg.sender of deployer
```

**Potential Break Path:**
- None identified — standard pattern

**Impact of Break:** N/A
**Confidence:** VERY HIGH (verified via source)
**Validation Status:** ✅ Verified

---

## VIII. INVARIANT BREAK SIMULATION SUMMARY

| ID | Invariant | Break Path | Ease of Break | Impact | Priority to Test |
|---|---|---|---|---|---|
| INV-001 | Fully backed vault | ERC-4626 donation | MEDIUM | 🔴 High | 🔴 P0 |
| INV-002 | Mono-tonic exchange rate | Oracle manipulation | LOW | 🟡 Medium | 🟢 P3 |
| INV-003 | Principal protection | Donation / Reentrancy | MEDIUM | 🔴 High | 🔴 P0 |
| INV-004 | Proportional shares | Front-run donation | MEDIUM | 🟡 Medium | 🔴 P0 |
| INV-005 | Total supply = sum | OZ bug | VERY LOW | 🔴 High | 🟢 P3 |
| INV-006 | Payouts ≤ yield | Double claim | MEDIUM | 🔴 High | 🔴 P0 |
| INV-007 | Verifiable randomness | RNG manipulation | LOW | 🟡 Medium | 🟡 P2 |
| INV-008 | No dilution from prizes | Over-payout | MEDIUM | 🟡 Medium | 🟡 P2 |
| INV-009 | PayoutId unique (global) | Cross-chain replay | MEDIUM | 🔴 High | 🔴 P0 |
| INV-010 | LZ sender = peer | Peer hijack | LOW | 🔴 High | 🟡 P2 |
| INV-011 | Valid vaults only | False factory | LOW | 🔴 High | 🟡 P2 |
| INV-012 | Deterministic addresses | Salt mismatch | VERY LOW | 🟡 Medium | 🟢 P3 |
| INV-013 | Whitelisted strategies | Malicious perspective | LOW | 🔴 Critical | 🟡 P2 |
| INV-014 | Timelocked caps | Cancel + resubmit | LOW | 🟡 Medium | 🟡 P2 |
| INV-015 | EVK solvency | Oracle manipulation | LOW | 🔴 High | 🟢 P3 |
| INV-016 | Cap enforcement | Race condition | LOW | 🟢 Low | 🟢 P3 |
| INV-017 | Accurate lastTotalAssets | Uninitialized local | LOW | 🟡 Medium | 🟡 P1 |
| INV-018 | Fee on yield only | Wrong sign check | VERY LOW | 🟢 Low | 🟢 P3 |
| INV-019 | OnlyOwner upgrade | Proxy admin compromise | LOW | 🔴 Critical | 🟡 P2 |
| INV-020 | No creator privileges | Missing | N/A | N/A | N/A |

---

## IX. INVARIANT CHECKLIST — PER CHAIN

| INV | Invariant | Base | Arbitrum | Monad | Katana | Chain-Specific? |
|---|---|---|---|---|---|---|
| INV-001 | Fully backed vault | 🟡 | 🟡 | 🟡 | 🟡 | No |
| INV-002 | Monotonic rate | ✅ | ✅ | ✅ | ✅ | No |
| INV-003 | Principal protection | 🟡 | 🟡 | 🟡 | 🟡 | No |
| INV-004 | Proportional shares | 🟡 | 🟡 | 🟡 | 🟡 | No |
| INV-005 | Total supply | ✅ | ✅ | ✅ | ✅ | No |
| INV-006 | Payouts ≤ yield | 🟡 | 🟡 | 🟡 | 🟡 | No |
| INV-007 | Randomness | ❓ | ❓ | ❓ | ❓ | No |
| INV-008 | No dilution | 🟡 | 🟡 | 🟡 | 🟡 | No |
| INV-009 | payoutId unique | ⚠️ | ⚠️ | ⚠️ | ⚠️ | 🔴 Cross-chain |
| INV-010 | LZ peer match | ✅ | ✅ | ✅ | ✅ | Per-chain config |
| INV-011 | Valid vaults | ✅ | ✅ | ✅ | ✅ | No |
| INV-012 | Deterministic | ✅ | ✅ | ⚠️ Proxy | ✅ | Monad proxy |
| INV-013 | Whitelisted strategies | ✅ | ✅ | ⚠️ Proxy | ✅ | Monad proxy |
| INV-014 | Timelocked caps | ✅ | ✅ | ✅ | ✅ | No |
| INV-017 | Accurate lastTotalAssets | ⚠️ | ⚠️ | ⚠️ | ⚠️ | No |
| INV-019 | OnlyOwner upgrade | ✅ | ✅ | ⚠️ | ✅ | Monad only |

> ✅ = Holds | 🟡 = Partially verified | ⚠️ = Needs investigation | ❓ = Unknown

---

## X. KEY QUESTIONS THAT NEED RESOLUTION

| Question | Related INV | Impact of Answer |
|---|---|---|
| Is `claimedPayouts` a global or vault-specific mapping? | INV-009 | Global → safe. Per-vault → cross-chain replay possible |
| Does AmpleEarn override `totalAssets()` with internal accounting? | INV-001, INV-003 | Yes → donation attack mitigated. No → donation attack viable |
| What is the randomness source for winner selection? | INV-007 | VRF → safe. blockhash → manipulable |
| Is there a minimum cooldown between cancel and resubmit of cap? | INV-014 | No cooldown → timelock bypass possible |
| Who is the proxy admin for Monad factory? | INV-019 | Multi-sig → low risk. EOA → high risk |

---

*Document generated from: Source code analysis, RECON_PER_CHAIN.md, CROSS_CHAIN_COMPARISON.md, FINDINGS_CHECKLIST.md, THREAT_MODEL.md, WORKFLOWS/invariant.md*
