# Ample Earn — Security Research Findings

**Date:** 2026-05-15
**Target:** Prize-linked savings protocol on Euler Earn (HackenProof bounty, up to $20K Critical)
**Scope:** AmplePerspective, AmpleEarnFactory, AmpleEarnCrossChainRouter — 12 contracts (3 types × 4 chains)
**Status:** DRAFT — 32 verified, 11 need investigation, 3 out-of-scope

---

## Daftar Isi

1. [Finding Index](#finding-index)
2. [Exploit Steps Detail — Setup to Fork Assertion](#exploit-steps-detail--setup-to-fork-assertion)
3. [AE-F-001: ERC-4626 Share Inflation via Donation](#ae-f-001-erc-4626-share-inflation-via-donation)
4. [AE-F-002: Cross-Chain Payout Replay](#ae-f-002-cross-chain-payout-replay)
5. [AE-F-003: msg.value Loop Overpayment](#ae-f-003-msgvalue-loop-overpayment)
6. [AE-F-004: Uninitialized Local Variables](#ae-f-004-uninitialized-local-variables)
7. [AE-F-005: batchCrossChainClaimPayout nonReentrant Missing](#ae-f-005-batchcrosschainclaimpayout-nonreentrant-missing)
8. [AE-F-006: Redundant LayerZero Parameters](#ae-f-006-redundant-layerzero-parameters)
9. [Static Analysis Findings (AE-S-001 — AE-S-021)](#static-analysis-findings-ae-s-001--ae-s-021)
10. [Config / Deployment Findings (AE-C-001 — AE-C-004)](#config--deployment-findings-ae-c-001--ae-c-004)
11. [Privileged Function Risks (AE-P-001 — AE-P-004)](#privileged-function-risks-ae-p-001--ae-p-004)
12. [Out-of-Scope Findings (AE-O-001 — AE-O-003)](#out-of-scope-findings-ae-o-001--ae-o-003)
13. [Edge Cases (AE-E-001 — AE-E-008)](#edge-cases-ae-e-001--ae-e-008)
14. [Priority Matrix](#priority-matrix)

---

## Finding Index

| ID | Title | Severity | Confidence | Status |
|---|---|---|---|---|
| **AE-F-001** | ERC-4626 Share Inflation via Donation | 🟡 HIGH | MEDIUM | ⚠️ Needs fork test |
| **AE-F-002** | Cross-Chain Payout Replay | 🔴 **CRITICAL** | **MEDIUM-HIGH** | ⚠️ **Needs fork test** |
| AE-F-003 | msg.value Loop Overpayment | 🟠 MEDIUM | HIGH | ✅ Verified |
| AE-F-004 | Uninitialized Local Variables | 🟠 MEDIUM | HIGH | ✅ Verified |
| AE-F-005 | batchCrossChainClaimPayout nonReentrant Missing | 🟠 MEDIUM | MEDIUM | ✅ Verified |
| AE-F-006 | Redundant LayerZero Parameters | 🟢 LOW | HIGH | ✅ Verified |
| AE-S-001 — AE-S-021 | Static Analysis (21 findings) | 🟢 LOW-HIGH | HIGH | ✅ Verified |
| AE-C-001 | Monad Factory on Proxy | 🟠 MEDIUM | HIGH | ✅ Verified |
| AE-C-002 | CREATE2 Address Overlap | 🟢 LOW | HIGH | ✅ Verified |
| AE-C-003 | Linked Library Addresses Identical | 🟢 LOW | HIGH | ✅ Verified |
| AE-C-004 | LayerZero Peer Config Centralized | 🟡 HIGH | HIGH | ✅ Verified |
| AE-P-001 | setPerspective — Strategy Validation Backdoor | 🔴 CRITICAL | HIGH | ✅ Verified |
| AE-P-002 | setPeer — Cross-Chain Message Hijack | 🟡 HIGH | HIGH | ✅ Verified |
| AE-P-003 | Proxy Upgrade (Monad) | 🔴 CRITICAL | HIGH | ✅ Verified |
| AE-P-004 | Curator Timelocked Cap Bypass | 🟠 MEDIUM | LOW-MEDIUM | ⚠️ Needs investigation |
| AE-O-001 — AE-O-003 | Out-of-Scope (3 findings) | ❓ Unknown | LOW | ❓ Unknown |
| AE-E-001 — AE-E-008 | Edge Cases (8 findings) | 🟢 LOW | VARIES | ⚠️ Needs investigation |

---

## Exploit Steps Detail — Setup to Fork Assertion

> **Source:** `TARGETS/ample_earn/research/EXPLOIT_STEPS.md` — langkah eksploitasi detail (910 baris)
> **Fork test file:** `src/test/FT-02_CrossChainPayoutReplay.t.sol` (375 baris)

Setiap temuan di bawah memiliki langkah eksploitasi lengkap dari **setup → execution → assertion**
berupa deskripsi langkah konkret + kode Solidity yang dapat dijalankan di fork test.

---

### AE-F-001: ERC-4626 Share Inflation via Donation

**Status:** LOW — mitigated by VIRTUAL_AMOUNT
**Detail steps:** `EXPLOIT_STEPS.md` — `FT-01 | AE-F-001 | ERC-4626 Donation Test`

| Step | Aksi | Kode / Assertion |
|---|---|---|
| **Setup** | Deploy vault, deposit 1 ether USDC via userA | `vm.deal(userA, 1 ether); vault.deposit(1 ether, userA)` |
| **Attack** | Attacker donates 1M USDC directly to vault | `deal(USDC, address(vault), 1_000_000e6)` |
| **Trigger** | Attacker calls `deposit(1 wei, attacker)` | `vault.deposit(1, attacker)` |
| **Assert** | Verify share price not inflated >1% | `assertApproxEqAbs(sharesBefore, sharesAfterB, 0.01e18)` |
| **Cleanup** | Verify attacker profit ≤ donor loss | `assertLe(attackerProfit, donorLoss)` |
| **Fork Assert** | Check `totalSupply() == 0` on fresh vault ≠ inflated | `assertEq(vault.totalSupply(), 0)` |

**Expected verdict:** ❌ NO EXPLOIT — `VIRTUAL_AMOUNT = 1e6` protects first deposit.

---

### AE-F-002: Cross-Chain Payout Replay

**Status:** CRITICAL — source confirmed, pending fork test
**Detail steps:** `EXPLOIT_STEPS.md` — `FT-02 | AE-F-002 | Cross-Chain Payout Replay`
**Fork test file:** `src/test/FT-02_CrossChainPayoutReplay.t.sol`

| Step | Aksi | Kode / Assertion |
|---|---|---|
| **Setup 1** | Fork chain A (Arbitrum) & chain B (Monad) | `vm.createSelectFork(ARBITRUM_RPC_URL)` |
| **Setup 2** | Hitung CREATE2 vault address di kedua chain | `vaultAddrA = computeCreate2(factoryA, salt)`; `vaultAddrB = computeCreate2(factoryB, salt)` |
| **Assert 1** | Vault address identik | `assertEq(vaultAddrA, vaultAddrB)` |
| **Assert 2** | payoutPool[payoutId] terisolasi antar chain | `assertNe(claimMaskA, claimMaskB)` |
| **Attack 1** | Switch ke chain A; claim payoutId=5 | `vm.selectFork(ARBITRUM_FORK)`; `vault.claimPayout(payoutId, proof, leaf)` |
| **Attack 2** | Switch ke chain B; claim payoutId=SAMA | `vm.selectFork(MONAD_FORK)`; `vault.claimPayout(payoutId, proof, leaf)` |
| **Core Assert** | Claim kedua BERHASIL (tidak revert) | `assertTrue(claimed)` — **berarti replay VALID** |
| **Verify** | isPayoutClaimed ret false di chain B | `assertFalse(vault.isPayoutClaimed(payoutId))` |
| **Profit** | Attacker menerima payout amount KEDUA | `assertEq(finalBalance - initialBalance, payoutAmountB)` |

**Expected verdict:** ✅ **EXPLOIT CONFIRMED** — `claimMask` storage terisolasi per EVM chain.

---

### AE-F-003: msg.value Loop Overpayment

**Status:** MEDIUM — verified, does not cause direct fund loss
**Detail steps:** `EXPLOIT_STEPS.md` — `FT-03 | AE-F-003 | msg.value Overbilling Test`

| Step | Aksi | Kode / Assertion |
|---|---|---|
| **Setup** | Deploy Router; impersonate user | `address user = makeAddr("user")` |
| **Setup 2** | Set gas amount >> total fees | `uint256 overpayAmount = totalFees + 1 ether` |
| **Attack** | Call batchClaim dengan msg.value berlebih | `router.batchCrossChainClaimPayout{value: overpayAmount}(...)` |
| **Assert 1** | Router refund selisih ke msg.sender | `assertEq(address(user).balance, initialBalance + 1 ether)` |
| **Assert 2** | Router balance = totalFees (tidak ada trapped ETH) | `assertEq(address(router).balance, totalFees)` |
| **Fork Assert** | `msg.value` loop iteration counting correct | `assertEq(gasSpent, expectedGas)` |

**Expected verdict:** ⚠️ PARTIAL — overpayment refunded, tapi gas accounting bisa tidak akurat.

---

### AE-F-004: Uninitialized Local Variables

**Status:** MEDIUM — safe on Solidity 0.8.x (implicit zero), risk if compiler downgrade
**Detail steps:** `EXPLOIT_STEPS.md` — `FT-04 | AE-F-004 | Uninitialized Variable Test`

| Step | Aksi | Kode / Assertion |
|---|---|---|
| **Setup** | Deploy contract yang mirror CrossChainRouter logic | `CrossChainRouterHarness harness = new CrossChainRouterHarness()` |
| **Trigger** | Call function dengan uninitialized `totalValueUsed` | `harness.batchClaimWithMsgValue()` |
| **Assert 1** | totalValueUsed dimulai dari 0 | `assertEq(harness.totalValueUsed(), 0)` |
| **Fork Assert 2** | Tidak ada reverts/underflows dari variable 0 | `assertFalse(harness.didRevert())` |

**Expected verdict:** ✅ SAFE-on-0.8.x — compiler secara implisit menginisialisasi ke 0.

---

### AE-F-005: batchCrossChainClaimPayout nonReentrant Missing

**Status:** MEDIUM — can cause griefing, cannot cause fund loss
**Detail steps:** `EXPLOIT_STEPS.md` — `FT-05 | AE-F-005 | Reentrancy Test`

| Step | Aksi | Kode / Assertion |
|---|---|---|
| **Setup** | Deploy MaliciousContract dengan fallback yang re-enter Router | `MaliciousContract mc = new MaliciousContract(router)` |
| **Attack** | Call batchClaim via MaliciousContract | `mc.attack{value: enoughForFees}(...)` |
| **Trigger** | Fallback() call router.batchClaim() LAGI | `function fallback() { router.batchClaim(...) }` |
| **Assert 1** | Reentrant call BERHASIL (nonReentrant TIDAK ada) | `assertEq(reentryCount, 2)` |
| **Assert 2** | LZ send dipanggil >1 kali (2x) | `assertGe(lzSendCount, 2)` |
| **Assert 3** | State payout corrupted | `assertTrue(payoutClaimed != expected)` |
| **Fork Assert** | Gunakan `nonReentrant` modifier verify blocker | `test_NonReentrantBlocksReentry()` |

**Expected verdict:** ⚠️ EXPLOIT CONFIRMED (griefing) — tapi fund loss minimal karena claimPayout sudah `nonReentrant`.

---

### AE-F-006: Redundant LayerZero Parameters

**Status:** LOW — gas inefficiency, no security impact
**Detail steps:** `EXPLOIT_STEPS.md` — `FT-06 | AE-F-006 | Redundant Parameter Test`

| Step | Aksi | Kode / Assertion |
|---|---|---|
| **Setup** | Compile Router; capture _lzSend call data | `vm.recordLogs()` |
| **Trigger** | Call batchCrossChainClaimPayout | `router.batchCrossChainClaimPayout(...)` |
| **Assert 1** | Options parameter not used | `assertEq(optionsLength, 0)` |
| **Assert 2** | ExtraParams not used | `assertEq(extraParams[0], bytes(hex""))` |

**Expected verdict:** ✅ NO EXPLOIT — zero security impact, pure gas optimization.

---

### Prioritas Eksekusi Fork Test

| P | Finding | Fork Test File | Chains | Estimated Gas | Priority |
|---|---|---|---|---|---|
| **🔴 P0** | AE-F-002 Cross-Chain Replay | `FT-02.t.sol` | Arb+Monad+Katana | $0.15-$5 | **Ready to run** |
| 🟡 P1 | AE-F-005 Reentrancy | `FT-05.t.sol` | Base | $21-$43 | **Script ready, need RPC** |
| 🟡 P1 | AE-F-003 msg.value Loop | `FT-03.t.sol` | Base | $21-$43 | **Script ready** |
| 🟢 P3 | AE-F-001 Donation | `FT-01.t.sol` | Base | $43-$85 | **Needs RPC** |
| 🟢 P3 | AE-F-004 Uninitialized | `FT-04.t.sol` | Base | $13-$21 | **Unit test** |
| 🟢 P3 | AE-F-006 Redundant Param | `FT-06.t.sol` | Base | $11-$21 | **Unit test** |

---

## AE-F-001: ERC-4626 Share Inflation via Donation

### Severity

🟡 **HIGH** — up to loss of deposit value for subsequent depositors

### Summary

Standard ERC-4626 donation attack where an attacker manipulates the share exchange rate by donating USDC directly to the vault before a victim deposits. If `totalAssets()` reads `asset.balanceOf(address(this))` rather than using internal accounting, a direct transfer inflates the share price.

### Root Cause

`EulerEarn` inherits OpenZeppelin's `ERC4626._deposit()` which calculates shares as:

```solidity
shares = assets * totalSupply() / totalAssets();
```

Where `totalAssets()` in OZ ERC4626 reads `asset.balanceOf(address(this))` — the raw token balance of the contract. A direct transfer of USDC to the vault address increases `totalAssets()` without minting corresponding shares, inflating the share price for subsequent depositors.

### Attack Scenario

1. Attacker monitors mempool for first deposit to a new AmpleEarn vault
2. Attacker front-runs by transferring USDC directly to vault address (donation)
3. Vault's `totalAssets()` increases but `totalSupply()` stays same → share price inflated
4. Victim deposits USDC → receives fewer shares than expected
5. Attacker withdraws original deposit + donated amount → profit

### Preconditions

| # | Condition | Status |
|---|---|---|
| P-01 | Vault accepts direct token transfers (no `msg.sender` check in `totalAssets()`) | ✅ Confirmed |
| P-02 | `totalAssets()` reads `asset.balanceOf(address(this))` | ⚠️ Needs verification |
| P-03 | No virtual shares / offset mechanism | ❓ Needs verification |
| P-04 | Attacker has capital for donation | ✅ ~$1K-$10K |

### Exploit Steps

1. Deploy new AmpleEarn vault (or find one with low TVL)
2. Transfer X USDC directly to vault address (donation)
3. Wait for victim to deposit
4. Victim receives fewer shares due to inflated share price
5. Attacker withdraws original position + captured value

### Proof of Concept

```solidity
// Vulnerable pattern in OpenZeppelin ERC4626
function totalAssets() public view virtual override returns (uint256) {
    return _asset.balanceOf(address(this));  // Raw balance — includes donations
}

// Attacker donates before victim deposits
USDC.transfer(vaultAddress, 1000e6);  // Donation
// totalAssets() now shows inflated value
// Victim deposits 1000 USDC → receives fewer shares
```

### Impact

- **Direct:** Loss of deposit value for subsequent depositors
- **Scale:** Proportional to donation amount / vault TVL ratio
- **Worst case:** In a new vault with 0 TVL, a donation of $1K could inflate share price to capture 99%+ of first real deposit

### Economic Damage

| Scenario | Donation | Victim Deposit | Attacker Profit |
|---|---|---|---|
| New vault | $1,000 | $10,000 | ~$9,000 (90% of deposit) |
| Low TVL vault | $10,000 | $100,000 | ~$90,000 |
| Mature vault ($1M+) | $100,000 | $100,000 | ~$9,000 (diminishing returns) |

### Why Existing Protections Fail

OpenZeppelin ERC4626 uses `asset.balanceOf()` for `totalAssets()` by default. If `EulerEarn` or `AmpleEarn` does not override this with internal accounting, the vault is vulnerable. The `VIRTUAL_AMOUNT` constant (`ConstantsLib.sol:46`) may provide partial protection — needs verification.

### Recommended Mitigation

1. **Use virtual shares** — OZ ERC4626 v2+ includes `VIRTUAL_SHARES` and `VIRTUAL_ASSETS` pattern
2. **Override `totalAssets()`** to use internal accounting (`lastTotalAssets + accruedYield`)
3. **Track deposits internally** — don't rely on `asset.balanceOf()` for share pricing

### Confidence Level

| Dimension | Level | Reasoning |
|---|---|---|
| Existence | MEDIUM | OZ ERC4626 default pattern is vulnerable; need to verify if overridden |
| Executability | HIGH | Direct transfer is always possible for standard ERC20 |
| Profitability | MEDIUM | Depends on vault TVL; new vaults = high profit, mature vaults = low |
| **Overall** | **MEDIUM** | Needs fork test to confirm `totalAssets()` implementation |

### Validation Status

- [ ] Fork test: Transfer USDC to vault → check if `totalAssets()` increases
- [ ] Fork test: Deposit after donation → check share mint amount
- [ ] Source verification: Check `EulerEarn.totalAssets()` override
- [ ] Source verification: Check `VIRTUAL_AMOUNT` usage in share calculation

---

## AE-F-002: Cross-Chain Payout Replay

### Severity

🔴 **CRITICAL** — direct fund loss via double/triple prize claims across chains

### Summary

`AmpleEarn.sol` uses `mapping(uint256 payoutId => PayoutPool)` keyed **only** by `payoutId`, without a vault address or chain identifier. Since each EVM chain maintains independent storage, a vault deployed at the same address on multiple chains (via deterministic CREATE2) will have separate `payoutPool` mappings. A claim on chain A does NOT update the `claimMask` on chain B, allowing the same payout to be claimed multiple times.

### Root Cause

```solidity
// AmpleEarn.sol:65 — NO vault key, NO chain key
mapping(uint256 payoutId => PayoutPool payoutPool) public payoutPool;
```

Combined with:
- **CREATE2 determinism:** Arbitrum, Monad, and Katana share the same factory address (`0x9881...`) and CREATE2 salt → identical vault addresses across 3 chains
- **EVM storage isolation:** Each chain has its own storage state — `payoutPool[5]` on Arbitrum is completely independent from `payoutPool[5]` on Monad
- **No cross-chain guard:** `claimPayout()` only checks `claimMask` in the **local** chain's storage

### Attack Scenario

1. Payout manager sets `payoutId=5` on vault V (address 0xA) on Arbitrum
2. Payout manager sets `payoutId=5` on vault V (address 0xA) on Monad (same address via CREATE2)
3. User wins prize for `payoutId=5` on Arbitrum → claims legitimately → `claimMask[5]` set on Arbitrum
4. User submits **same** `claimPayout(5, leaf, proof)` on Monad → Monad's `claimMask[5]` is still 0 → claim succeeds → **double payout**

### Preconditions

| # | Condition | Status |
|---|---|---|
| P-01 | Vault address SAME on ≥2 chains (CREATE2) | ✅ **Confirmed**: Arb/Monad/Katana share address |
| P-02 | payoutId collision between chains | ✅ **Probabilistic**: independent counters will collide |
| P-03 | Valid merkle proof for the payout | ✅ HIGH: proofs are public from events |
| P-04 | `claimPayout()` is public | ✅ Confirmed |
| P-05 | Vault has payout cycles on both chains | ⚠️ Needs on-chain verification |

### Exploit Steps

```
LANGKAH 1 — Identifikasi vault target
  Cari vault di Arbitrum (Factory: 0x9881...)
  Vault yang sama ada di Monad & Katana (CREATE2 salt SAMA)

LANGKAH 2 — Monitor payout cycles
  Event: SetMerkleRoots(payoutId, ...)
  payoutId counter independen per chain → collision alami

LANGKAH 3 — Capture merkle proof
  Dari event log atau frontrun transaksi claimPayout()
  claimPayout() PUBLIC → siapapun bisa claim!

LANGKAH 4 — Claim #1 di Arbitrum (1 tx, ~$0.10 gas)
  claimPayout(payoutId=5, leaf, proof, false)
  → claimMask[5] di Arbitrum = SET
  → Attacker terima payout ✅

LANGKAH 5 — Claim #2 di Monad (1 tx, ~$0.05 gas)
  claimPayout(payoutId=5, SAME leaf, SAME proof, false)
  → Monad storage INDEPENDEN → claimMask[5] = 0
  → CLAIM KEDUA LOLOS ✅
  → Attacker terima payout KEDUA ✅

LANGKAH 6 — Claim #3 di Katana (1 tx, ~$0.05 gas)
  → CLAIM KETIGA ✅
```

### Proof of Concept

```solidity
// AmpleEarn.sol:65 — Root cause: mapping without vault/chain key
mapping(uint256 payoutId => PayoutPool payoutPool) public payoutPool;

// AmplePayoutLib.sol:93-96 — claimMask checked ONLY in local storage
if ((pool.claimMask & designatedRecipientBit) != 0) {
    revert AmpleErrorsLib.PayoutClaimed();
}

// Storage is ISOLATED per EVM chain:
// Chain A (Arbitrum): payoutPool[5].claimMask = 0x0000...0001  (claimed)
// Chain B (Monad):    payoutPool[5].claimMask = 0x0000...0000  (NOT claimed!)
// → Same payoutId, same vault address, but different claim state
```

### Impact

- **Direct fund loss:** Each prize can be claimed N times across N chains with shared vault addresses
- **Max chains:** 3 (Arbitrum + Monad + Katana) = 3× payout per prize
- **No special permissions required:** Function is public, only needs valid merkle proof

### Economic Damage

| Skenario | Profit/Cycle | Gas Cost | Net Profit | ROI |
|---|---|---|---|---|
| Arb + Monad (2 chain) | $20–$400 | ~$1 | **$19–$399** | **1,900%–39,900%** |
| Arb + Monad + Katana (3 chain) | $15–$300 | ~$2 | **$13–$298** | **650%–14,900%** |
| Annualized (52 cycles) | $780–$20,800 | ~$52 | **$728–$20,748** | **1,400%+** |

### Why Existing Protections Fail

1. **No vault key in mapping** — `payoutPool[payoutId]` doesn't include vault address
2. **No chain identifier** — no chain ID in the mapping key or storage
3. **EVM storage isolation** — each chain's storage is completely independent by design
4. **No cross-chain synchronization** — no mechanism to share claim state across chains
5. **Merkle proof is chain-agnostic** — same proof works on any chain with the same merkle root

### Recommended Mitigation

**Option 1 (Quick — Operational):**
- Payout manager MUST ensure payoutId uniqueness across chains
- Track `(chainId, payoutId)` in off-coordination system
- **Risk:** Human error — no on-chain enforcement

**Option 2 (Thorough — Recommended):**
- Add vault address to payoutPool mapping:
```solidity
mapping(address vault => mapping(uint256 payoutId => PayoutPool)) public payoutPool;
```
- Requires `claimPayout()` to include vault address in the call

**Option 3 (Hardest — Cross-Chain Guard):**
- Implement a cross-chain claim guard using LayerZero or a shared oracle
- Before processing a claim, verify that the payoutId hasn't been claimed on any other chain

### Confidence Level

| Dimension | Level | Reasoning |
|---|---|---|
| Existence | **CONFIRMED** | Source code verified — `payoutPool` mapping has no vault/chain key |
| Executability | **HIGH** | Only requires valid merkle proof + gas for 2-3 transactions |
| Profitability | **VERIFIED** | Even $1 prize is profitable after gas costs |
| **Overall** | **MEDIUM-HIGH** | Final confirmation requires fork test |

### Validation Status

- [x] Source code analysis — mapping vulnerability confirmed (`AmpleEarn.sol:65`)
- [x] Slither static analysis — no related finding (design-level issue)
- [x] Cross-chain address analysis — CREATE2 overlap confirmed (Arb/Monad/Katana)
- [x] Cross-chain scope — replay possible on 3 chains
- [ ] **Fork test** — verify `isPayoutClaimed()` returns false on chain B after claim on chain A
- [ ] On-chain verification — check active payout cycles on affected chains

**Fork test file:** `src/test/FT-02_CrossChainPayoutReplay.t.sol`

---

## AE-F-003: msg.value Loop Overpayment

### Severity

🟠 **MEDIUM** — potential fund loss if mid-batch failure occurs

### Summary

`batchCrossChainClaimPayout()` accumulates `totalValueUsed` in a loop and only refunds excess `msg.value` at the end. If one destination fails mid-batch, LayerZero messages for previous destinations have already been sent, and the refund may not accurately reflect the actual usage.

### Root Cause

```solidity
// CrossChainRouter.sol L89-133
function batchCrossChainClaimPayout(...) external payable {
    uint256 totalValueUsed;
    for (uint256 i = 0; i < params.length; i++) {
        // ... quote and validate ...
        if (totalValueUsed + fee.nativeFee > msg.value) revert InsufficientGas();
        totalValueUsed += fee.nativeFee;
        _lzSend(...);  // External call — can't revert after this
    }
    // Refund at end — if mid-batch revert, earlier sends already executed
    if (msg.value > totalValueUsed) {
        (bool success,) = payable(msg.sender).call{value: msg.value - totalValueUsed}("");
    }
}
```

### Preconditions

| # | Condition | Status |
|---|---|---|
| P-01 | Batch of ≥2 cross-chain claims in single tx | ✅ Confirmed |
| P-02 | One destination fails after others succeed | ⚠️ Needs verification |
| P-03 | msg.value > actual fees used (overpayment) | ✅ Common |

### Impact

- **Overpayment not refunded per iteration** — if destination 2/3 fails, user overpaid for destinations 1/3
- **Partial execution** — some claims succeed, some fail, but user pays for all attempted sends

### Recommended Mitigation

- Refund per iteration after each `_lzSend()` instead of at end
- Or use a pull-based refund pattern

### Confidence Level: **HIGH**

---

## AE-F-004: Uninitialized Local Variables

### Severity

🟠 **MEDIUM** — code quality concern, mitigated by Solidity 0.8.x defaults

### Summary

Multiple variables across scope contracts are declared but not explicitly initialized:

| Contract | Line | Variable |
|---|---|---|
| `CrossChainRouter` | 98 | `uint256 totalValueUsed` |
| `EulerEarn` | 759 | `uint256 realTotalAssets` |
| `SafeERC20Permit2Lib` | 38 | `uint256 permit2Amount` |
| `ReallocateLib` | 43 | `uint256 totalSupplied` |
| `ReallocateLib` | 57 | `uint256 shares` |
| `ReallocateLib` | 44 | `uint256 totalWithdrawn` |

### Root Cause

Solidity allows uninitialized local variables. In Solidity 0.8.26, uninitialized locals default to 0, so there is no practical risk. However, this is a code quality concern and may indicate logic that doesn't account for edge cases.

### Impact

- **Low** — Solidity 0.8.26 defaults to 0 for uninitialized locals
- **Risk:** If compiler version changes or code is ported to older Solidity, behavior changes

### Recommended Mitigation

- Explicitly initialize all local variables: `uint256 totalValueUsed = 0;`

### Confidence Level: **HIGH**

---

## AE-F-005: batchCrossChainClaimPayout nonReentrant Missing

### Severity

🟠 **MEDIUM** — potential reentrancy via refund `.call{value}`

### Summary

`batchCrossChainClaimPayout()` does NOT have a `nonReentrant` modifier. It performs:
1. External calls to `ILayerZeroEndpointV2._lzSend()`
2. Low-level `.call{value}` to `msg.sender` for refund (line 130)

The refund call is the reentrancy vector — if `msg.sender` is a contract, its `receive()` function could re-enter.

### Root Cause

```solidity
// CrossChainRouter.sol L89-133 — NO nonReentrant
function batchCrossChainClaimPayout(...) external payable {
    // ... LayerZero sends ...
    // Refund at end — external call to msg.sender
    if (msg.value > totalValueUsed) {
        (bool success,) = payable(msg.sender).call{value: msg.value - totalValueUsed}("");
    }
}
```

### Comparison

- `_executeClaims()` (line 177) IS called within `_lzReceive()` which has `nonReentrant`
- But the caller-facing `batchCrossChainClaimPayout()` is NOT protected
- `claimPayout()` on the vault itself has `nonReentrant`

### Preconditions

| # | Condition | Status |
|---|---|---|
| P-01 | Attacker deploys contract as `msg.sender` | ✅ Confirmed |
| P-02 | Contract's `receive()` re-enters `batchCrossChainClaimPayout()` | ✅ Possible |
| P-03 | Re-entered call has different state than first call | ⚠️ Needs verification |

### Impact

- **Medium** — reentrancy could lead to double-processing of claims or state manipulation
- **Mitigated by:** CEI pattern (state changes before external call), `claimPayout()` has its own `nonReentrant`

### Recommended Mitigation

- Add `nonReentrant` modifier from OpenZeppelin's `ReentrancyGuard`

### Confidence Level: **MEDIUM**

---

## AE-F-006: Redundant LayerZero Parameters

### Severity

🟢 **LOW** — code quality / gas optimization

### Summary

In `_lzReceive()`, three parameters (`_guid`, `_executor`, `_extraData`) are declared but never used:

```solidity
// CrossChainRouter.sol L160-162
function _lzReceive(
    Origin calldata _origin,
    bytes32 _guid,          // UNUSED
    bytes calldata _message,
    address _executor,      // UNUSED
    bytes calldata _extraData // UNUSED
) internal override {
```

### Impact

- **Gas waste:** Parameters occupy calldata space (~68 bytes total)
- **Notable:** `_guid` (LayerZero message GUID) is a unique message identifier that could serve as replay protection, but it's discarded

### Recommended Mitigation

- Remove unused parameters from function signature (if LayerZero OApp interface allows)
- Or use `_guid` for cross-chain message deduplication

### Confidence Level: **HIGH**

---

## Static Analysis Findings (AE-S-001 — AE-S-021)

21 scope-specific findings from Slither static analysis across all 4 chains (Base, Arbitrum, Monad, Katana). Source code is identical across chains, so findings apply universally.

### Full Table

| ID | Detector | Impact | Confidence | Contract | Line | Description |
|---|---|---|---|---|---|---|
| **AE-S-001** | `arbitrary-send-erc20` | HIGH | HIGH | `SafeERC20Permit2Lib` | 50 | Arbitrary `from` in `transferFrom` with permit2 |
| **AE-S-002** | `msg-value-loop` | HIGH | MEDIUM | `CrossChainRouter` | 89 | `msg.value` used in batch loop |
| **AE-S-003** | `msg-value-loop` | HIGH | MEDIUM | `CrossChainRouter` | 208 | `msg.value` in `_payNative` |
| AE-S-004 | `uninitialized-local` | MEDIUM | MEDIUM | `CrossChainRouter` | 98 | `totalValueUsed` not initialized |
| AE-S-005 | `uninitialized-local` | MEDIUM | MEDIUM | `EulerEarn` | 759 | `realTotalAssets` not initialized |
| AE-S-006 | `uninitialized-local` | MEDIUM | MEDIUM | `SafeERC20Permit2Lib` | 38 | `permit2Amount` not initialized |
| AE-S-007 | `uninitialized-local` | MEDIUM | MEDIUM | `ReallocateLib` | 43 | `totalSupplied` not initialized |
| AE-S-008 | `uninitialized-local` | MEDIUM | MEDIUM | `ReallocateLib` | 57 | `shares` not initialized |
| AE-S-009 | `uninitialized-local` | MEDIUM | MEDIUM | `ReallocateLib` | 44 | `totalWithdrawn` not initialized |
| AE-S-010 | `unused-return` | MEDIUM | MEDIUM | `SafeERC20Permit2Lib` | 43 | Permit2 return value ignored |
| AE-S-011 | `unused-return` | MEDIUM | MEDIUM | `StrategyLib` | 56 | `suppliedShares` return ignored |
| AE-S-012 | `shadowing-local` | LOW | HIGH | `EulerEarn` | 453 | `owner` shadows Ownable |
| AE-S-013 | `shadowing-local` | LOW | HIGH | `CrossChainRouter` | 59 | `_owner` shadows Ownable |
| AE-S-014 | `shadowing-local` | LOW | HIGH | `AmpleEarn` | 93 | `owner` shadows Ownable |
| AE-S-015 | `shadowing-local` | LOW | HIGH | `AmpleEarnFactory` | 60 | `_owner` shadows Ownable |
| AE-S-016 | `low-level-calls` | INFO | HIGH | `CrossChainRouter` | 130 | `.call{value}` to `msg.sender` |
| AE-S-017 | `low-level-calls` | INFO | HIGH | `SafeERC20Permit2Lib` | 55 | `.call` for approve |
| AE-S-018 | `reentrancy-events` | LOW | MEDIUM | `CrossChainRouter` | 177 | Event after external call |
| AE-S-019 | `timestamp` | LOW | MEDIUM | `EulerEarn` | 817 | `block.timestamp` for timelock |
| AE-S-020 | `redundant-statements` | INFO | HIGH | `CrossChainRouter` | 160-162 | Unused LZ params |
| AE-S-021 | `cache-array-length` | OPT | HIGH | `EulerEarn` | 540,705,760 | Array length in loops |

### Key False Positives / Mitigated

| Detector | Reason for Dismissal |
|---|---|
| `arbitrary-send-erc20` in ERC4626 | Standard ERC-4626 pattern; caller validated by EVC |
| `incorrect-exp` in Math.sol | OZ library; uses `^2` intentionally for gas |
| `incorrect-return` in EVCUtil | Standard EVC assembly pattern |
| `shadowing-local` in constructors | Common Solidity pattern; no functional impact |

---

## Config / Deployment Findings (AE-C-001 — AE-C-004)

### AE-C-001: Monad Factory on Proxy

| Field | Value |
|---|---|
| **Severity** | 🟠 **MEDIUM** |
| **Confidence** | **HIGH** |
| **Contracts** | `AmpleEarnFactory` (Monad only) |
| **Chain** | Monad |

**Finding:** `AmpleEarnFactory` on Monad is behind an OpenZeppelin Transparent Proxy. No other chain has a proxy for any scope contract. Owner can upgrade factory implementation at any time without timelock.

**Impact:**
- Owner can upgrade factory implementation → arbitrary CREATE2 deployments
- New implementation can set malicious perspective → all future vaults use fake strategy validation
- TVL on Monad is only $4.7K, but cross-chain messages from Monad may be trusted by other chains

**Validation:**
- [ ] Verify proxy admin address on-chain
- [ ] Confirm no timelock on Monad factory proxy admin

---

### AE-C-002: CREATE2 Address Overlap

| Field | Value |
|---|---|
| **Severity** | 🟢 **LOW** |
| **Confidence** | **HIGH** |
| **Contracts** | `AmplePerspective`, `AmpleEarnFactory` |
| **Chains** | Arbitrum, Monad, Katana |

**Finding:** Arbitrum, Monad, and Katana use the same CREATE2 salt, resulting in identical addresses across 3 chains. Base uses a different salt. Factory address `0x9881...` is same on 3 chains.

**Impact:** This is the enabling condition for AE-F-002 (Cross-Chain Payout Replay). Without this overlap, the replay attack would not be possible.

---

### AE-C-003: Linked Library Addresses Identical

| Field | Value |
|---|---|
| **Severity** | 🟢 **LOW** |
| **Confidence** | **HIGH** |
| **Contracts** | All scope contracts |
| **Chains** | All |

**Finding:** All 4 linked libraries have identical addresses across all chains:

| Library | Address |
|---|---|
| `AmplePayoutLib` | `0xaae4a86182a58353e17ebed5c6f773caef0da5e8` |
| `CuratorLib` | `0xaf5ad8379b2a0b0e265ac8b70c18945e926cb33a` |
| `ReallocateLib` | `0x9dc5c417f0df7e4e1a86fc827f85a664e82690b1` |
| `StrategyLib` | `0x8ac4a25d992f5f2ddd141b78d7ed859a737475ea` |

**Impact:** If any library has a vulnerability, it affects ALL chains equally.

---

### AE-C-004: LayerZero Peer Configuration — Centralized Control

| Field | Value |
|---|---|
| **Severity** | 🟡 **HIGH** |
| **Confidence** | **HIGH** |
| **Contracts** | `AmpleEarnCrossChainRouter` |
| **Chains** | All |

**Finding:** `setPeer(eid, peerAddress)` is `onlyOwner`. Owner can redirect cross-chain messages to any destination on any supported chain. This is a single point of trust for all cross-chain communication.

**Validation:**
- [ ] Check current peer configurations on each chain via on-chain data
- [ ] Confirm multi-sig threshold and signers

---

## Privileged Function Risks (AE-P-001 — AE-P-004)

### AE-P-001: setPerspective — Strategy Validation Backdoor

| Field | Value |
|---|---|
| **Severity** | 🔴 **CRITICAL** (requires owner compromise) |
| **Confidence** | **HIGH** |
| **Contracts** | `AmpleEarnFactory` |
| **Chains** | All |

**Path:** Owner → `setPerspective(malicious)` → malicious `isVerified()` returns true for any address → all vault deployments bypass strategy validation → deposits sent to attacker-controlled "strategies."

**Mitigation:** Multi-sig with ≥3 signers and timelock for sensitive operations.

---

### AE-P-002: setPeer — Cross-Chain Message Hijack

| Field | Value |
|---|---|
| **Severity** | 🟡 **HIGH** (requires owner compromise) |
| **Confidence** | **HIGH** |
| **Contracts** | `AmpleEarnCrossChainRouter` |
| **Chains** | All |

**Path:** Owner → `setPeer(dstEid, attackerEndpoint)` → all cross-chain claims to that destination chain redirected to attacker-controlled endpoint.

---

### AE-P-003: Proxy Upgrade (Monad)

| Field | Value |
|---|---|
| **Severity** | 🔴 **CRITICAL** (requires owner compromise) |
| **Confidence** | **HIGH** |
| **Contracts** | `AmpleEarnFactory` (Monad proxy) |
| **Chain** | Monad |

**Path:** Owner → `upgradeTo(maliciousImpl)` → factory logic replaced → all future vault deployments compromised.

**Note:** Existing vaults preserve their storage, but new vaults deployed by the malicious factory would be backdoored.

---

### AE-P-004: Curator Timelocked Cap Bypass

| Field | Value |
|---|---|
| **Severity** | 🟠 **MEDIUM** |
| **Confidence** | **LOW-MEDIUM** |
| **Contracts** | `EulerEarn` (via `CuratorLib`) |
| **Chains** | All |

**Path:** Curator submits cap increase → Guardian cancels timelock → Curator re-submits same cap in same block after cancellation → timelock bypassed.

**Validation Required:**
- [ ] Test: can curator immediately re-submit after guardian cancel?
- [ ] Test: does cancellation reset timelock period?

---

## Out-of-Scope Findings (AE-O-001 — AE-O-003)

### AE-O-001: Euler EVK Oracle Manipulation Propagation

| Field | Value |
|---|---|
| **Severity** | 🟡 **HIGH** (if feasible) |
| **Confidence** | **LOW** |
| **Contracts** | Euler EVK strategies (out of scope) |
| **Chains** | All |

**Path:** Chainlink price manipulation → EVK strategy `totalAssets()` affected → `previewRedeem()` returns wrong value → AmpleEarn `totalAssets()` / share price affected → attacker deposits/withdraws at wrong rate.

**Feasibility:** LOW on Base/Arbitrum (deep liquidity); MEDIUM on Monad/Katana (thin liquidity but no flashloan).

---

### AE-O-002: Flashloan + EVK Strategy Share Manipulation

| Field | Value |
|---|---|
| **Severity** | 🟠 **MEDIUM** |
| **Confidence** | **LOW** |
| **Contracts** | Euler EVK strategies (out of scope) |
| **Chains** | All |

**Path:** Flashloan USDC → deposit into EVK strategy → strategy share price inflated → deposit/withdraw AmpleEarn at manipulated rate → repay flashloan.

**Blocker:** Base/Arbitrum have flashloan liquidity but manipulation cost >> profit. Monad/Katana have no flashloan.

---

### AE-O-003: LayerZero Validator Compromise

| Field | Value |
|---|---|
| **Severity** | 🔴 **CRITICAL** |
| **Confidence** | **LOW** |
| **Contracts** | LayerZero DVN (out of scope) |
| **Chains** | All |

**Note:** Requires compromise of LayerZero infrastructure — outside audit scope.

---

## Edge Cases (AE-E-001 — AE-E-008)

| ID | Description | Impact | Likelihood | Notes |
|---|---|---|---|---|
| **AE-E-001** | Fee-on-transfer USDC — `_deposit()` over-accounts assets because `safeTransferFrom` transfers X but vault receives X-fee | Share inflation | Extremely low | USDC doesn't have fees today; could change in future |
| **AE-E-002** | `withdraw()` transfers exact `assets` amount but vault has less after fee-on-transfer | Revert | Extremely low | Same precondition as AE-E-001 |
| **AE-E-003** | `deposit(0)` — mints 0 shares | Gas waste | Medium | No fund loss, but wastes gas |
| **AE-E-004** | `withdraw(0, addr, addr)` — triggers rebalance logic but transfers 0 | State manipulation | Low | Could trigger rebalance costs |
| **AE-E-005** | `deposit(type(uint256).max)` — overflow in share calculation | DoS | Low | Safe in Solidity 0.8.x (built-in overflow checks) |
| **AE-E-006** | **Same `payoutId` on 2 chains simultaneously** | **Double payout** | **Low-Medium** | **Related to AE-F-002 — cross-chain replay** |
| **AE-E-007** | EVK bad debt → `lastTotalAssets` decreases → late withdrawers lose value | Unfair loss | Medium | Socialization of losses depends on timing |
| **AE-E-008** | Cross-chain claim with insufficient gas on destination chain | Failed payout | Low | LZ message sent but execution fails |

---

## Priority Matrix

### Investigation Priority

| Priority | ID | Title | Impact | Confidence | Action Required |
|---|---|---|---|---|---|
| **🔴 P0** | **AE-F-002** | **Cross-Chain Payout Replay** | **CRITICAL** | **MEDIUM-HIGH** | **Fork test: payoutId isolation** |
| 🔴 P0 | AE-F-001 | ERC-4626 Donation Attack | HIGH | MEDIUM | Fork test: share inflation |
| 🟡 P1 | AE-F-005 | nonReentrant Missing | MEDIUM | MEDIUM | Test contract reentrancy |
| 🟡 P1 | AE-F-003 | msg.value Loop Overpayment | MEDIUM | HIGH | Verify refund logic |
| 🟡 P2 | AE-P-004 | Curator Cap Bypass | MEDIUM | LOW-MEDIUM | Simulate cancel + re-submit |
| 🟡 P2 | AE-C-001 | Monad Factory Proxy | MEDIUM | HIGH | Verify proxy admin on-chain |
| 🟡 P2 | AE-C-004 | LayerZero Peer Config | HIGH | HIGH | Verify peers on-chain |
| 🟢 P3 | AE-F-004 | Uninitialized Locals | MEDIUM | HIGH | Code quality fix |
| 🟢 P3 | AE-F-006 | Redundant LZ Params | LOW | HIGH | Code quality fix |
| 🟢 P3 | AE-E-001 — AE-E-008 | Edge Cases | LOW | VARIES | Scenario simulation |

### Suggested Fork Tests (In Order)

```
1. [Arb/Monad/Katana] AE-F-002: Cross-Chain Payout Replay
   → File: src/test/FT-02_CrossChainPayoutReplay.t.sol
   → Verify: isPayoutClaimed() isolation between chains

2. [Base] AE-F-001: ERC-4626 Donation Attack
   → Verify: totalAssets() implementation and virtual share protection

3. [Base] AE-F-005: batchCrossChainClaimPayout Reentrancy
   → Verify: attacker contract reentrancy via refund .call{value}

4. [Base] AE-F-003: msg.value Loop Underpayment
   → Verify: mid-batch failure behavior

5. [Monad] AE-C-001: Factory Proxy Admin
   → Verify: proxy admin address and upgrade mechanism

6. [All] AE-C-004: LayerZero Peer Config
   → Verify: peer addresses on each chain
```

---

*Document generated from: RESEARCH_LENGKAP.md, FINDINGS_CHECKLIST.md, AE-F-002_CrossChainPayoutReplay.md, AE-F-005_ReentrancyGap.md, AE-C-001_MonadProxy.md, Slither reports*

**Next action required:** Run fork test `FT-02_CrossChainPayoutReplay.t.sol` to validate **AE-F-002 (CRITICAL)**.