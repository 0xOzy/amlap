# Accounting & Business Logic Invariants — Ample Earn

**Date:** 2026-05-15  
**Target:** Ample Earn — Prize-linked savings on Euler Earn  
**Scope:** AmplePerspective, AmpleEarnFactory, AmpleEarnCrossChainRouter, EulerEarn, AmpleEarn, AmpleEarnReserve, AmplePayoutLib  
**Chains:** Base, Arbitrum, Monad, Katana  
**Template:** `templates/invariant_template.md`

---

## Legend

| Simbol | Arti |
|---|---|
| `totalSUP` | `totalSupply()` |
| `totalASS` | `totalAssets()` |
| `lastTA` | `lastTotalAssets` |
| `VA` | `VIRTUAL_AMOUNT` (`1e6`) |

---

# Invariant: VI-1 — Share Pricing With Virtual Amount Protection

## Description

The amount of shares minted for a deposit (or assets returned for a withdrawal) per ERC-4626 is:

```
shares_minted = assets_deposited * (totalSUP + VA) / (totalASS + VA)
assets_redeemed = shares_burned * (totalASS + VA) / (totalSUP + VA)
```

Where `VA = VIRTUAL_AMOUNT = 1e6` is added to both numerator and denominator.

**Source:** `src/EulerEarn.sol:570-592` | `ConstantsLib.VIRTUAL_AMOUNT` di `src/libraries/ConstantsLib.sol:46`

```solidity
function _convertToSharesWithTotals(assets, newTotalSupply, newTotalAssets, rounding)
    returns (uint256) {
    return assets.mulDiv(
        newTotalSupply + ConstantsLib.VIRTUAL_AMOUNT,
        newTotalAssets + ConstantsLib.VIRTUAL_AMOUNT,
        rounding
    );
}
```

## Why It Must Hold

Tanpa `VIRTUAL_AMOUNT`, seorang attacker bisa melakukan **first-deposit donation attack**:
1. Deposit 1 wei → terima 1 share
2. Donate 1000 USDC langsung ke vault → `totalASS` naik, `totalSUP` tetap
3. Setiap share sekarang bernilai jauh lebih besar
4. Depositor berikutnya menerima sangat sedikit share

Dengan `VA = 1e6`, pada deposit pertama:
```
shares = assets * (0 + 1e6) / (0 + 1e6) = assets
```
Setelah donasi D: `shares = assets * (S + 1e6) / (A + D + 1e6)` — efek donasi didilusi oleh VA.

Ini adalah **satu-satunya mekanisme** yang melindungi depositor dari share inflation. Jika invariant ini rusak, semua depositor bisa diekstrak nilainya.

## Potential Break Path

1. **Donasi langsung ke vault**: USDC dikirim `transfer(vault, amount)` → `totalASS` naik, `totalSUP` tetap → exchange rate berubah. Tapi dengan VA, efeknya didilusi.
2. **Flashloan + strategy share manipulation**: Manipulasi `previewRedeem()` di strategy vault → `totalASS()` berubah sementara → exchange rate sementara tidak akurat. **Bukan kegagalan invariant pricing**, tapi manipulasi input.
3. **Rounding exploit**: Deposit/withdraw berulang dalam jumlah kecil. Tapi FLOOR untuk deposit dan CEIL untuk withdraw membuat vault selalu untung atau break even.

## Exploitability

| Faktor | Rating |
|---|---|
| **Difficulty** | LOW (donation attack) / HIGH (flashloan manipulation) |
| **Capital Required** | MODERATE — $1K–$10K untuk donasi berarti |
| **Technical Skill** | LOW |
| **Exploitability** | **LOW** (dilindungi VA) |

## Impact

Jika VA tidak ada atau diabaikan:

| Chain | TVL | Max Loss |
|---|---|---|
| Base | $4.33M | Semua dana depositor |
| Arbitrum | $118K | Semua dana depositor |
| Monad | $4.7K | Semua dana depositor |
| Katana | $5.7K | Semua dana depositor |

Dengan VA: **proteksi efektif** — serangan donation tidak menguntungkan.

## Validation Method

1. **Unit test**: Simulasi deposit pertama dengan donasi 10,000 USDC
2. **Fork test**: Deposit di Base vault, kirim donasi, verifikasi exchange rate hanya berubah sesuai formula
3. **Slither**: Verifikasi tidak ada override `_convertToShares`/`_convertToAssets` yang menghilangkan VA

## Confidence

**VERY HIGH** — VA = 1e6 di-hardcode di ConstantsLib, digunakan di semua fungsi konversi, dan merupakan pola standar yang sudah battle-tested.

---

# Invariant: VI-2 — Deposit Proportionality (FLOOR Rounding)

## Description

```
deposit(assets) → shares = _convertToSharesWithTotals(assets, totalSUP, lastTA, FLOOR)
require(shares > 0)

mint(shares) → assets = _convertToAssetsWithTotals(shares, totalSUP, lastTA, CEIL)
```

**Source:** `src/EulerEarn.sol:467-475` (deposit), `src/EulerEarn.sol:478-484` (mint)

## Why It Must Hold

Depositor harus menerima jumlah share yang proporsional dengan kontribusinya. FLOOR rounding memastikan vault tidak pernah memberikan lebih banyak share daripada yang seharusnya (proteksi terhadap depositor lain). CEIL pada mint memastikan vault menerima aset yang cukup untuk menutupi shares yang diminta.

Tanpa invariant ini:
- Depositor bisa menerima lebih banyak share dari yang seharusnya
- Dilusi terhadap depositor lain
- Potensi arbitrase

## Potential Break Path

1. **0-amount deposit**: `assets = 0` → `shares = 0` → revert `ZeroShares` (aman)
2. **Dust deposit**: Jumlah sangat kecil sehingga `shares = 0` → revert (aman — melindungi dari spam)
3. **Front-running**: Attacker donasi sebelum deposit victim → exchange rate berubah → victim terima share lebih sedikit. Ini BUKAN break invariant pricing, tapi manipulasi timing. Dibatasi oleh VA.

## Exploitability

| Faktor | Rating |
|---|---|
| **Difficulty** | LOW (front-run) |
| **Capital Required** | MODERATE |
| **Exploitability** | **LOW** (VA protects) |

## Impact

Rendah — VA melindungi dari ekstraksi nilai signifikan.

## Validation Method

1. **Fork test**: Deposit dengan berbagai jumlah di fork Base, verifikasi formula
2. **Edge case**: Deposit 0 → harus revert

## Confidence

**VERY HIGH** — OZ ERC4626 standard + VA protection.

---

# Invariant: VI-3 — Withdraw Proportionality (FLOOR/CEIL Rounding)

## Description

```
withdraw(assets) → shares = _convertToSharesWithTotals(assets, totalSUP, lastTA, CEIL)
redeem(shares) → assets = _convertToAssetsWithTotals(shares, totalSUP, lastTA, FLOOR)
```

**Source:** `src/EulerEarn.sol:487-500` (withdraw), `src/EulerEarn.sol:503-510` (redeem), `src/EulerEarn.sol:636-646` (_redeem)

## Why It Must Hold

CEIL pada withdraw: user memberikan shares yang cukup (atau lebih) untuk menarik aset yang diinginkan. FLOOR pada redeem: user menerima aset yang cukup (atau kurang) untuk shares yang dibakar. Kombinasi ini memastikan vault tidak pernah dirugikan oleh rounding.

## Potential Break Path

1. **Dust withdrawal**: Withdraw nilai sangat kecil → `shares` bisa 1 atau lebih, vault mungkin rugi secara proporsional
2. **Last depositor**: Ketika hanya 1 depositor tersisa, `totalSUP == balanceOf(lastUser)`. Redeem semua shares harus memberikan semua `totalASS`. `_redeem()` L643 mengasumsikan "exchange rate is never < 1". Jika ada realized loss, asumsi ini salah.

## Exploitability

| Faktor | Rating |
|---|---|
| **Last depositor loss** | MEDIUM |
| **Exploitability** | **LOW** (realized losses jarang) |

## Impact

Last depositor menanggung semua realized loss — risiko yang melekat pada semua ERC-4626 vault.

## Validation Method

1. **Fork test**: Redeem seluruh shares sebagai single depositor, bandingkan dengan `totalASS`
2. **Edge case**: Withdraw 1 wei → verifikasi rounding

## Confidence

**VERY HIGH** — OZ ERC4626 standard.

---

# Invariant: VI-4 — totalAssets() ≥ lastTotalAssets (No Negative Yield)

## Description

```
newTotalAssets = realTotalAssets + newLostAssets
               ≥ lastTotalAssetsCached
```

**Source:** `src/EulerEarn.sol:753-783`

## Why It Must Hold

`totalAssets()` dipanggil oleh `_accruedFeeAndAssets()` yang menghitung:

```solidity
if (realTotalAssets < lastTotalAssetsCached - lostAssets) {
    newLostAssets = lastTotalAssetsCached - realTotalAssets;  // absorb losses
}
newTotalAssets = realTotalAssets + newLostAssets;
```

`lostAssets` adalah **buffer** yang menyerap kerugian strategi. Ketika `realTotalAssets` turun, `newLostAssets` naik sehingga:

```
newTotalAssets = realTotalAssets + (lastTotalAssetsCached - realTotalAssets)
               = lastTotalAssetsCached
```

**Invariant selalu terjaga** — `totalAssets()` tidak pernah turun di bawah `lastTotalAssets`. Kerugian hanya tercermin sebagai peningkatan `lostAssets`, bukan penurunan `totalAssets()`.

## Potential Break Path

1. **Temporary desync**: `_deposit()` update `lastTA += assets` SEBELUM `supplyStrategy()`. Jika supply gagal, `lastTA > totalAssets()`. Diperbaiki di `_accrueInterest()` berikutnya.
2. **Realized loss beruntun**: Nilai `lostAssets` terus meningkat — bukan break invariant, tapi indikasi strategi tidak sehat.

## Exploitability

| Faktor | Rating |
|---|---|
| **Difficulty** | HIGH — butuh strategi rugi |
| **Exploitability** | **LOW** (mekanisme disengaja) |

## Impact

Tidak ada dampak langsung — `lostAssets` hanya menunda kerugian. Tapi jika `lostAssets` sangat besar, fee shares berkurang.

## Validation Method

1. **Slither**: Verifikasi `_accruedFeeAndAssets()` tidak bisa return `newTotalAssets < lastTotalAssets`
2. **Fork test**: Simulasi realized loss di strategy, verifikasi `lostAssets` naik

## Confidence

**HIGH** — formula sudah benar secara matematis.

---

# Invariant: VI-5 — Fee Only From Positive Yield

## Description

```
fee_shares > 0  ONLY IF  (newTotalAssets - lastTotalAssetsCached) > 0
```

**Source:** `src/EulerEarn.sol:776-783`

## Why It Must Hold

```solidity
uint256 totalInterest = newTotalAssets - lastTotalAssetsCached;
if (totalInterest != 0 && fee != 0) {
    uint256 feeAssets = totalInterest.mulDiv(fee, WAD);
    feeShares = _convertToSharesWithTotals(feeAssets, totalSUP, newTotalAssets - feeAssets, FLOOR);
}
```

Fee hanya dihitung dari positive interest (`newTotalAssets > lastTotalAssets`). Untuk AmpleEarn, `fee = 1e18` (100%), jadi `feeAssets = totalInterest` — **semua yield masuk ke payout reserve**.

## Potential Break Path

1. **Tidak ada** — logic `if (totalInterest != 0 && fee != 0)` sudah benar
2. **Jika `fee = 0`**: Tidak ada fee yang di-mint (protokol bisa set fee ke 0)

## Exploitability

**NONE** — invariant tidak bisa di-break.

## Impact

N/A — invariant selalu terjaga.

## Validation Method

1. **Source review**: Verifikasi `totalInterest` hanya positif
2. **Unit test**: Simulasi yield = 0 → fee = 0

## Confidence

**VERY HIGH**.

---

# Invariant: VI-6 — Protocol Fee Deducted From Vault Fee

## Description

```
protocolFeeShares = feeShares * protocolFee / WAD  (FLOOR)
vaultFeeShares = feeShares - protocolFeeShares
```

**Source:** `src/EulerEarn.sol:734-744`

## Why It Must Hold

Protocol fee adalah % dari vault fee, bukan % dari total yield. Jika `protocolFee = 10%` dan yield = 1000:
- `feeAssets = 1000` (vault fee 100%)
- `protocolFeeShares = feeShares * 0.1e18 / 1e18 = 10% dari feeShares`
- 90% feeShares ke vault (payout reserve), 10% ke protocol

Ini memastikan protocol hanya mengambil cut dari fee yang benar-benar dihasilkan vault.

## Potential Break Path

1. **Jika protocolFee = 0**: Semua feeShares ke vault, protocol dapat 0 — ini disengaja
2. **Jika protocolFee > 1e18**: Revert di constructor (`MAX_FEE = 1e18`)

## Exploitability

**NONE**.

## Validation Method

1. **Source review**: Verifikasi formula
2. **Unit test**: protocolFee = 0, 10%, 50%

## Confidence

**VERY HIGH**.

---

# Invariant: PI-1 — Single Claim Per Payout Per Recipient (Bitmask)

## Description

```
For each (payoutId, designatedRecipientIndex):
    (payoutPool[payoutId].claimMask & (1 << designatedRecipientIndex)) can only be set ONCE.
```

**Source:** `src/ample/AmpleEarn.sol:288-296`, `src/ample/libraries/AmplePayoutLib.sol:93-96`

## Why It Must Hold

```solidity
uint256 designatedRecipientBit = uint256(1) << designatedRecipientLeaf.designatedRecipientIndex;
if ((pool.claimMask & designatedRecipientBit) != 0) revert PayoutClaimed();
payoutPool.claimMask |= designatedRecipientBit;
```

Setiap designated recipient dalam satu payout cycle hanya bisa mengklaim SATU KALI. Bitmask memastikan exactly-once semantics dalam satu vault.

## Potential Break Path

1. **Cross-chain replay (KRITIS)**: `payoutPool` dipetakan oleh `payoutId` SAJA — tidak ada vault atau chain key. Chain yang berbeda punya storage terpisah, sehingga:
   - Claim di Base → set `claimMask` bit di Base storage
   - Claim di Arbitrum → cek `claimMask` bit di Arbitrum storage → **MASIH FALSE**
   - **Payout diklaim dua kali**
   
   Lihat **XI-1** untuk detail lengkap.

2. **Reentrancy**: Jika `claimPayout()` dipanggil berulang sebelum `claimMask` diupdate. Tapi `claimMask |= bit` terjadi SEBELUM transfer (CEI pattern) — **aman**.

## Exploitability

| Faktor | Rating |
|---|---|
| Difficulty (same chain) | N/A — protected |
| Difficulty (cross-chain) | LOW |
| **Exploitability (cross-chain)** | **MEDIUM-HIGH** |
| **Exploitability (same chain)** | **NONE** |

## Impact

| Skenario | Dampak |
|---|---|
| Same chain | ✅ Tidak bisa — bitmask proteksi |
| Cross-chain (XI-1) | 🔴 **CRITICAL** — replay payout di chain lain |

## Validation Method

1. **Unit test**: Claim payout yang sama 2× di chain yang sama → revert
2. **Fork test (KRITIS)**: Claim payoutId=5 di Base, lalu claim payoutId=5 di Arbitrum → **seharusnya juga revert?** → **FORK TEST UNTUK VERIFIKASI**

## Confidence

**VERY HIGH** (same chain) | **MEDIUM** (cross-chain — verified via source, need fork test)

---

# Invariant: PI-2 — Payout Accounting Consistency

## Description

```
totalPayoutsClaimed ≤ totalPayoutsReserved  (at all times)
accruedInterestInPayoutReserve ≤ balanceOf(PAYOUT_RESERVE) - totalPayoutsReserved
```

**Source:** `src/ample/AmpleEarn.sol:170-176` (PI-4), `src/ample/AmpleEarn.sol:240-241` (PI-3)

## Why It Must Hold

**PI-4** memastikan payout manager tidak bisa mengalokasikan yield yang tidak ada:
```solidity
uint256 available = balanceOf(PAYOUT_RESERVE) - totalPayoutsReserved;
if (accruedInterest > available) revert;
```

**PI-3** memastikan total payout yang diklaim tidak melebihi yang direservasi:
```solidity
totalPayoutsClaimed += payoutAmount;
totalPayoutsReserved -= payoutAmount;
```

## Potential Break Path

1. **Cancel payout**: `totalPayoutsReserved -= remainingPayoutAmount` — aman
2. **Double claim (cross-chain)**: Jika payoutId direplay di chain lain, total payout di chain A mungkin exceed reserve di chain A. Tapi reserve dan claim bersifat per-chain — chain B tidak tahu chain A sudah claim. **Ini adalah masalah desain, bukan break invariant di chain individual.**

## Exploitability

**NONE** (same chain) | **MEDIUM-HIGH** (cross-chain via replay)

## Impact

Same chain: ✅ Aman. Cross-chain: 🔴 Payout melebihi yield.

## Validation Method

1. **Source review**: Verifikasi formula accounting
2. **Fork test**: Cross-chain replay → verifikasi dampak pada reserve

## Confidence

**VERY HIGH** (same chain).

---

# Invariant: XI-1 — PayoutId Namespace Is PER-VAULT (Cross-Chain Replay)

## Description

```
payoutPool[payoutId] is scoped to the vault contract
  → NO vault key, NO chain key in the mapping
  → Each chain's vault has INDEPENDENT payoutPool storage
```

**Source:** `src/ample/AmpleEarn.sol:65`:

```solidity
mapping(uint256 payoutId => PayoutPool payoutPool) public payoutPool;
```

## Why It Must Hold

Ini adalah **kritikal desain question**. Jika invariant ini "hold" (per-vault namespace), maka:

- Chain A vault: `payoutPool[5].claimMask` di storage Chain A
- Chain B vault (address SAMA via CREATE2): `payoutPool[5].claimMask` di storage Chain B
- **Claim di Chain A TIDAK mempengaruhi claim status di Chain B**
- → **Cross-chain replay MUNGKIN**

Jika seharusnya invariant ini TIDAK hold (harusnya global), maka desain saat ini **SALAH**.

## Potential Break Path

Lihat T-01 di THREAT_LIST.md untuk detail lengkap. Intinya:

1. Vault address SAMA di 3 chain (Arbitrum, Monad, Katana) via CREATE2
2. Merkle root yang SAMA di-deploy di beberapa chain
3. Claim payoutId=5 di Chain A → storage Chain A updated
4. Claim payoutId=5 di Chain B → storage Chain B is EMPTY → claim sukses
5. **Payout diterima 2× dari 1 kemenangan**

## Exploitability

| Faktor | Rating |
|---|---|
| Difficulty | LOW |
| Capital Required | VERY LOW ($20–$200) |
| Technical Skill | LOW-MEDIUM |
| **Exploitability** | **MEDIUM-HIGH** |

## Impact

🔴 **CRITICAL** — Payout bisa diklaim N kali (N = jumlah chain dengan vault yang sama).

| Scenario | Payout Diterima |
|---|---|
| 1 kemenangan, 1 chain | 1× |
| 1 kemenangan, N chain | N× (drain protocol) |

## Validation Method

1. **Fork test (Base + Arbitrum)**: Deploy merkle root yang sama, claim payoutId yang sama di kedua chain
2. **Storage verification**: Gunakan `vm.storageAt()` untuk verifikasi storage layout `payoutPool`

## Confidence

**VERY HIGH** — verified via source code.

---

# Invariant: FI-1 — CREATE2 Vault Address Determinism

## Description

```
AmpleEarn address = CREATE2(deployer, salt, initcode)
  where salt = keccak256(abi.encodePacked(custodian, name, symbol))
```

**Source:** `AmpleEarnFactory.sol`

## Why It Must Hold

Cross-chain claims bergantung pada vault address yang sama di semua chain. Jika address berbeda, `isVault()` akan return false untuk vault di chain lain, dan cross-chain claim gagal.

CREATE2 menjamin bahwa `deployer + salt + initcode` yang sama menghasilkan address yang sama di EVM mana pun.

## Potential Break Path

1. **Deployer berbeda**: Factory address berbeda → vault di-chain A ≠ vault di-chain B
2. **Monad proxy**: Factory di Monad adalah proxy → CREATE2 dieksekusi oleh implementation contract (bukan proxy). Address tetap deterministic karena bytecode implementation sama.

## Exploitability

**NONE** — CREATE2 adalah invariant EVM.

## Impact

Jika rusak: semua cross-chain claim gagal.

## Validation Method

1. **Cross-chain verification**: Bandingkan vault address di Base, Arbitrum, Monad, Katana
2. **Already confirmed**: Arbitrum, Monad, Katana sharing address yang sama

## Confidence

**VERY HIGH**.

---

# Invariant: FI-2 — Strategy Must Be Verified by Perspective

## Description

```
createAmpleEarn() succeeds ONLY IF IAmplePerspective(perspective).isVerified(address(vault)) == true
```

## Why It Must Hold

Factory harus memvalidasi bahwa vault yang akan di-deploy aman. Perspective contract adalah whitelist — hanya vault yang sudah diverifikasi owner yang bisa di-deploy.

## Potential Break Path

1. **Owner setPerspective(malicious)**: Owner deploy perspective palsu yang return `true` untuk semua address → **bypass whitelist**. Ini adalah privileged function risk (AE-P-001), bukan break invariant — invariant tetap terjaga (isVerified tetap dipanggil).

## Exploitability

| Faktor | Rating |
|---|---|
| Without malicious owner | NONE |
| With malicious owner | LOW (butuh multi-sig) |

## Impact

Jika owner set malicious perspective: semua vault baru bisa di-deploy dengan strategi fake → 🔴 **dana depositor hilang**.

## Validation Method

1. **Source review**: Verifikasi `isVerified()` dipanggil di `createAmpleEarn()`
2. **Fork test**: Verifikasi bahwa vault tanpa verifikasi tidak bisa di-deploy

## Confidence

**VERY HIGH**.

---

# Invariant: NI-1 — No ERC-4626 First-Deposit Inflation

## Description

```
Donation attack is NOT profitable because VIRTUAL_AMOUNT = 1e6 dilutes the inflation.
```

**Source:** `src/libraries/ConstantsLib.sol:46`, `src/EulerEarn.sol:576-577`

## Why It Must Hold

Tanpa VA: deposit 1 wei → 1 share. Donate $10K USDC → share price = $10K. Depositor berikutnya deposit $10K → hanya terima 1 share.

Dengan VA:
- Deposit pertama: `shares = assets * 1e6 / 1e6 = assets`
- Donasi $10K: `totalASS += $10K` (misal 10,000,000,000), `totalSUP += assets`
- Share price: `(totalASS + 1e6) / (totalSUP + 1e6)` ≈ mendekati 1:1
- Donasi tidak menguntungkan

## Potential Break Path

1. **Jika VA dihapus atau di-override**: Tidak ada — VA di hardcode di ConstantsLib
2. **Jika ada vault dengan `_decimalsOffset()` berbeda**: EulerEarn tidak override `_decimalsOffset()`, jadi VA digunakan langsung

## Exploitability

**NONE** (protected by VA).

## Validation Method

1. **Source review**: Verifikasi VA digunakan di semua fungsi konversi
2. **Fork test**: Simulasi donation attack — verifikasi tidak profitable

## Confidence

**VERY HIGH**.

---

# Invariant: NI-2 — No Share Price Rounding Exploitation

## Description

```
deposit() → FLOOR rounding (vault untung)
withdraw() → CEIL rounding (vault untung)
mint() → CEIL rounding (vault untung)
redeem() → FLOOR rounding (vault untung)
```

Kombinasi: vault selalu diuntungkan dari rounding, atau break even.

## Why It Must Hold

Jika ada mismatch rounding (misal deposit CEIL dan withdraw FLOOR), attacker bisa:
1. Deposit X → terima banyak shares (CEIL)
2. Withdraw shares → terima banyak assets (FLOOR)
3. Profit dari selisih rounding

Kombinasi saat ini mencegah ini.

## Potential Break Path

1. **Tidak ada** — rounding sudah benar

## Exploitability

**NONE**.

## Validation Method

1. **Source review**: Verifikasi rounding direction per fungsi
2. **Unit test**: Deposit 1 → withdraw 1, verifikasi vault tidak rugi

## Confidence

**VERY HIGH**.

---

# Invariant: NI-3 — No Reentrancy in Core Operations

## Description

```
deposit() ✅ nonReentrant
withdraw() ✅ nonReentrant
mint() ✅ nonReentrant
redeem() ✅ nonReentrant
claimPayout() ✅ nonReentrant
setMerkleRoots() ✅ nonReentrant
batchCrossChainClaimPayout() ❌ NON REENTRANT
```

**Source:** Semua fungsi EulerEarn, AmpleEarn, dan CrossChainRouter.

## Why It Must Hold

Reentrancy bisa menyebabkan:
1. State berubah di tengah eksekusi → invariant sementara broken
2. Multiple claim dari satu transaksi
3. Manipulasi accounting

## Potential Break Path

`batchCrossChainClaimPayout()` (CrossChainRouter.sol:89-133) tidak punya `nonReentrant`. Fungsi ini:
1. Loop: send LayerZero messages (L115-117)
2. Akhir: `.call{value}` refund ke `msg.sender` (L130)

Jika `msg.sender` adalah contract, refund call bisa memicu reentrancy.

## Exploitability

| Faktor | Rating |
|---|---|
| Difficulty | MEDIUM |
| Capital Required | LOW (~$30–$200) |
| Technical Skill | MEDIUM |
| **Exploitability** | **MEDIUM** |

## Impact

Potensi double-claim atau state inconsistency pada cross-chain claims.

## Validation Method

1. **Fork test**: Deploy reentrancy contract, panggil `batchCrossChainClaimPayout()`, verifikasi apakah state bisa dimanipulasi

## Confidence

**HIGH** — satu gap teridentifikasi.

---

# Invariant Failure Simulation Matrix

| ID | Invariant | Break Scenario | Ease | Impact | Priority |
|---|---|---|---|---|---|
| VI-1 | Share pricing with VA | Donation to vault | LOW | MEDIUM | 🟢 P3 |
| **XI-1** | payoutId per-vault namespace | **Cross-chain replay** | **LOW** | **CRITICAL** | 🔴 **P0** |
| PI-2 | Payout accounting | Cross-chain double claim | MEDIUM | CRITICAL | 🔴 P0 |
| NI-3 | Reentrancy guard | batchCrossChainClaimPayout | MEDIUM | MEDIUM | 🟡 P1 |
| FI-2 | Perspective verification | Owner malicious | MEDIUM | CRITICAL | 🟡 P2 |

---

*Reformatted from `ACCOUNTING_INVARIANTS.md` using `templates/invariant_template.md`.*
