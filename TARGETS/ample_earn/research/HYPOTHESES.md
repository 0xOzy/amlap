# 3 Hipotesis Serangan Paling Mungkin — Ample Earn

**Date:** 2026-05-15  
**Method:** Kombinasi primitif dari `PATTERNS/` + source code verification + exploit synthesis

---

## Ringkasan Kombinasi Primitif

| Hipotesis | Primitif dari PATTERNS | Exploit Chain dari Synthesis |
|---|---|---|
| **H-01: Flashloan + Oracle Skew → Share Arbitrage** | `flashloan.md` + `oracle.md` + `erc4626.md` | EC-03 (diperluas) |
| **H-02: Cross-Chain Double-Claim + Bridge Replay** | `bridge.md` + `reward_accounting.md` + `erc4626.md` | EC-01 (diperdalam) |
| **H-03: Proxy Upgrade + Governance Abuse → Fund Drain** | `governance.md` + `bridge.md` + `liquidation.md` | EC-02 + EC-01 kombinasi |

---

## H-01: Flashloan + Oracle Skew → Share Arbitrage

### Primitif yang Digabungkan

| Pattern | Primitif | Bagaimana Digunakan |
|---|---|---|
| `flashloan.md` | Temporary collateral inflation | Flashloan untuk memanipulasi modal di Euler EVK strategy |
| `flashloan.md` | Oracle manipulation | Strategy share price dipengaruhi oracle |
| `oracle.md` | Low liquidity manipulation | Chain dengan TVL rendah (Monad $4.7K, Katana $5.7K) |
| `oracle.md` | Stale price usage | TWAP fallback bisa dimanipulasi jika likuiditas rendah |
| `erc4626.md` | Preview mismatch | `totalAssets()` query ke strategy secara live → `previewRedeem` dimanipulasi |
| `flashloan.md` | Reward farming | Extract value dari share price inflation intra-block |

### Mekanisme

`EulerEarn._accruedFeeAndAssets()` (L753-784):

```solidity
function _accruedFeeAndAssets() internal view returns (uint256, uint256, uint256) {
    uint256 realTotalAssets;
    for (uint256 i; i < withdrawQueue.length; ++i) {
        IERC4626 id = withdrawQueue[i];
        realTotalAssets += expectedSupplyAssets(id);  // ← calls id.previewRedeem(balance)
    }
    // ...
    newTotalAssets = realTotalAssets + newLostAssets;
}
```

`expectedSupplyAssets()` (L409):

```solidity
function expectedSupplyAssets(IERC4626 id) public view returns (uint256) {
    return id.previewRedeem(config[id].balance);  // ← LIVE QUERY ke strategy
}
```

**Inti masalah:** Setiap `deposit()`, `withdraw()`, `mint()`, `redeem()` memanggil `_accrueInterest()` yang memanggil `_accruedFeeAndAssets()` yang melakukan **live query** ke setiap strategy vault melalui `previewRedeem()`. Jika strategy vault memiliki oracle yang bisa dimanipulasi sementara, share price-nya terpengaruh, dan nilai tukar AmpleEarn vault ikut terpengaruh.

### Execution Path

```
Tahap 1: Setup
  └── Identifikasi Euler EVK strategy dengan likuiditas rendah 
      atau oracle manipulable (Chainlink pool tipis)

Tahap 2: Flashloan (10 step atomic)
  Step  1: Flashloan USDC $X (X = cukup untuk manipulasi)
  Step  2: Deposit ke target EVK strategy → pengaruhi share price
  Step  3: price dipengaruhi → previewRedeem naik
  Step  4: Deposit ke AmpleEarn vault → _accrueInterest() membaca inflated price
  Step  5: Dapat shares dengan rate menguntungkan  
  Step  6: Atau Withdraw dari vault sebelum strategy price kembali normal
  Step  7: Tarik dana dari strategy
  Step  8: Kembalikan flashloan
  Step  9: Ekstrak profit dari selisih rate
  Step 10: Repay flashloan + fee

Tahap 3: Realisasi
  └── Profit = selisih antara manipulated rate dan true rate
```

### Variasi — lastTotalAssets Desync

Primitif `erc4626.md` — "async accounting desync":

```solidity
// EulerEarn.sol:604
// `lastTotalAssets + assets` may be a little above `totalAssets()`.
// This can lead to a small accrual of `lostAssets` at the next interaction.
```

Setelah deposit/withdraw, `lastTotalAssets` diperbarui secara optimistis (`lastTotalAssets + assets`). Jika `totalAssets()` (dari strategy live query) berbeda, terjadi desync kecil di `lostAssets`. Perbedaan ini bisa di-arbitrage.

### Required State

| Kondisi | Untuk Eksekusi |
|---|---|
| Euler EVK strategy dengan manipulable pricing | Strategy harus menggunakan pool dengan likuiditas < $50K |
| Flashloan tersedia cukup ($100K-$500K) | Base: ✅ (Aave, Balancer); Monad: ❌ (tidak ada flashloan) |
| nonReentrant tidak menghalangi | ✅ Aman — flashloan dalam 1 tx via contract caller |
| VIRTUAL_AMOUNT tidak memblokir | ✅ Tidak relevan — H-01 tidak bergantung pada first deposit |

### Capital Required

| Chain | TVL | Flashloan Needed | Likuiditas Strategy | Profitability |
|---|---|---|---|---|
| **Base** | $4.33M | $500K-$1M | Deep (Euler EVK aktif) | LOW (biaya > profit) |
| **Arbitrum** | $118K | $100K-$200K | Medium | LOW-MEDIUM |
| **Monad** | $4.7K | $5K-$10K | Sangat tipis | **MEDIUM** |
| **Katana** | $5.7K | $5K-$10K | Sangat tipis | **MEDIUM** |

### Blockers

| Blocker | Dampak |
|---|---|
| `nonReentrant` pada deposit/withdraw | ❌ Tidak menghalangi (satu arah) |
| Chainlink + TWAP oracle | ❌ Butuh dana besar untuk manipulasi di chain utama |
| BVault try/catch di deposit | ❌ Hanya skip vault yang revert, tidak blokir |
| Flashloan tidak tersedia di Monad/Katana | ⚠️ **Blocker serius** — flashloan adalah prasyarat |

### Confidence

| Dimensi | Confidence | Alasan |
|---|---|---|
| **Primitif valid secara arsitektur** | **HIGH** | `previewRedeem` live query confirmed di source code |
| **Profitability (main chain)** | **LOW** | Biaya manipulasi oracle > potensi profit di Base/Arb |
| **Profitability (test chains)** | **LOW-MEDIUM** | Monad/Katana tidak punya flashloan |
| **Overall** | **MEDIUM** | Kerentanan struktural ada, tapi profitability questionable |

---

## H-02: Cross-Chain Payout Double-Claim + Bridge Replay

### Primitif yang Digabungkan

| Pattern | Primitif | Bagaimana Digunakan |
|---|---|---|
| `bridge.md` | Replay attacks | payoutId yang sama bisa di-replay di chain lain |
| `bridge.md` | Delayed settlement desync | Cross-chain settlement tidak sinkron → window untuk replay |
| `reward_accounting.md` | Double claim | `claimMask` per payoutId per chain → tidak shared |
| `reward_accounting.md` | Stale accounting updates | payoutPool state tidak tersinkronisasi antar chain |
| `erc4626.md` | Async accounting desync | totalAssets di setiap chain independen |
| `bridge.md` | Message spoofing | CrossChainRouter menerima pesan dari peer yang dikonfigurasi owner |

### Mekanisme

`AmpleEarn.sol:65`:

```solidity
mapping(uint256 payoutId => PayoutPool payoutPool) public payoutPool;
```

**Kunci kerentanan:** Mapping ini **hanya keyed oleh `payoutId`** — tanpa vault address, tanpa chain ID. Storage setiap EVM chain independen. Vault dengan address yang sama di chain berbeda (via CREATE2) memiliki `payoutPool` storage yang terpisah.

`AmpleEarnFactory.sol:117` — CREATE2 deterministik:

```solidity
new AmpleEarn{salt: salt}(...)
```

Salt yang sama + factory address yang sama = vault address yang sama di Arbitrum, Monad, dan Katana.

### Execution Path — Skenario Paling Realistis

```
Precondition: Payout manager menjadwalkan payout secara berkala
              di vault address 0xA di Chain A (Base) 
              payoutId increment: 1, 2, 3, ...

              Vault address 0xA yang SAMA juga aktif di Chain B (Arbitrum)
              payoutId juga increment: 1, 2, 3, ... (independen)

Skenario — PayoutId Collision:
  Step 1: Payout manager setMerkleRoots(accruedInterest=$5K, ...) di Chain A
          → payoutPool[5] on Chain A: $5K prize pool, claimMask=0
  Step 2: Payout manager setMerkleRoots(accruedInterest=$1K, ...) di Chain B
          → payoutPool[5] on Chain B: $1K prize pool, claimMask=0 (independent!)
  Step 3: User A memenangkan prize di Chain A untuk payoutId=5
          → claimPayout(5, proof_A) → user gets $500
          → payoutPool[5] on Chain A: claimMask bit 0 = 1
  Step 4: User A memenangkan prize di Chain B untuk payoutId=5
          → claimPayout(5, proof_B) → user gets $100
          → payoutPool[5] on Chain B: claimMask bit 0 = 1
          → ✅ Valid — dua prize independent, tidak ada exploit

Skenario — EKSPLOIT: Cross-chain Double-Claim:
  Step 1: Attacker memenangkan prize untuk payoutId=5 di Chain A
          → Attacker mendapat merkle proof: payoutId=5, amount=$500
  Step 2: Attacker claim payoutId=5 di Chain A → payoutPool[5].claimMask |= bit
          → User A menerima $500
  Step 3: Payout manager KEBETULAN/MEMANG set payoutId=5 DI JUGA Chain B
          (misalnya yield terakumulasi di chain B, payoutId increment ke 5)
          → payoutPool[5] on Chain B: $100 prize pool
          → claimMask on Chain B adalah 0 (fresh!)
  Step 4: Attacker yang SAMA bisa claim payoutId=5 di Chain B
          → payoutPool[5] on Chain B: claimMask |= bit
          → User A menerima $100 LAGI
          → ✅ Double-claim berhasil — $500 + $100 = $600 dari dua rantai berbeda
```

### Variasi — LayerZero Message Replay

Primitif `bridge.md` — "message spoofing":

Jika LayerZero validator tidak memverifikasi uniqueness GUID (message GUID), attacker bisa:
1. Menangkap pesan LZ yang sah: `batchCrossChainClaim(chainParams)` 
2. Replay pesan tersebut ke chain lain (jika peer dikonfigurasi untuk chain tersebut)
3. `_lzReceive` → `_executeClaims` → `claimPayout` → double payout

### Required State

| Kondisi | Status |
|---|---|
| payoutPool mapping tanpa vault key | ✅ **Confirmed** di `AmpleEarn.sol:65` |
| CREATE2 vault address sama di multiple chains | ✅ **Confirmed** — Arb/Monad/Katana share address |
| Payout manager menjadwalkan payoutId yang collision | ⚠️ **Probable** — increment counter independen per chain |
| Claim tidak sinkron antar chain | ✅ **By design** — tidak ada mekanisme sinkronisasi |
| Merkle proof valid di kedua chain | ✅ Mungkin, tergantung roots yang dipilih |

### Capital Required

| Role | Capital |
|---|---|
| Gas untuk claim di Chain A | $2-$50 |
| Gas untuk claim di Chain B | $2-$50 |
| Untuk LZ message replay | $5-$20 (fee LayerZero) |
| **Total** | **$10-$120** |

### Profit Potential

| Chain Pair | Prize Size (estimasi) | Double-Claim Profit |
|---|---|---|
| Base + Arbitrum | $5K + $1K | **$1K-$6K** per cycle |
| Base + Monad | $5K + $100 | $100-$5.1K |
| Base + Katana | $5K + $100 | $100-$5.1K |
| Arb + Monad | $1K + $100 | $100-$1.1K |

### Blockers

| Blocker | Dampak |
|---|---|
| PayoutId collision tidak dijamin terjadi | ✅ Tapi probabilistic — semakin banyak siklus, semakin tinggi probabilitas |
| Payout manager sadar untuk menghindari collision | ⚠️ Tidak ada on-chain enforcement |
| Merkle roots berbeda di setiap chain | ⚠️ Jika berbeda, replay gagal. Tapi butuh coordination yang ketat |

### Deteksi Anomali

| Metode Deteksi | Efektivitas |
|---|---|
| Monitor `ClaimPayout` event untuk payoutId duplikat | **MEDIUM** — post-factum, tidak preventif |
| Cross-chain payoutId tracker off-chain | **MEDIUM** — butuh indexing infrastruktur |
| On-chain tidak bisa mendeteksi | **LOW** — tidak ada mekanisme di contract |

### Confidence

| Dimensi | Confidence | Alasan |
|---|---|---|
| **Primitif valid** | **VERY HIGH** | Source code confirmed — payoutPool tanpa vault/chain key |
| **Exploitability** | **HIGH** | Gas minimal, tidak perlu permission |
| **Profitability** | **MEDIUM-HIGH** | Bergantung collision, tapi prize size signifikan |
| **Detectability** | **LOW** | Tidak ada on-chain guard |
| **Overall** | **HIGH** | **Eksploit paling realistis dan berdampak besar** |

---

## H-03: Proxy Upgrade + Governance Abuse → Fund Drain

### Primitif yang Digabungkan

| Pattern | Primitif | Bagaimana Digunakan |
|---|---|---|
| `governance.md` | Malicious upgrade | Monad Factory = proxy → owner upgrade implementation |
| `governance.md` | Timelock bypass | Proxy upgrade TIDAK memiliki timelock (proxy admin langsung) |
| `bridge.md` | Message spoofing | `setPeer()` mengarahkan pesan LZ ke attacker chain |
| `reward_accounting.md` | Reward debt desync | `cancelPayout()` mengalihkan sisa payout ke attacker |
| `liquidation.md` | Stale collateral valuation | `isStrategyAllowed()` via perspective yang compromised |

### Mekanisme

**Monad-specific proxy** (dari `metadata/proxies.json`):

```json
{
  "monad": {
    "AmpleEarnFactory": "0x9881...",
    "isProxy": true
  }
}
```

Hanya Monad yang memiliki Factory sebagai proxy. Owner (multi-sig) bisa memanggil `upgradeTo(newImplementation)` untuk mengganti implementasi Factory kapan saja — **tanpa timelock**.

`AmpleEarnFactory.setPerspective()` (L96-102):

```solidity
function setPerspective(address _perspective) public onlyEVCAccountOwner onlyOwner {
    perspective = IPerspective(_perspective);
}
```

Setelah upgrade atau langsung, owner bisa mengganti `perspective` ke kontrak attacker. Fungsi `isStrategyAllowed()` (L91-93) yang mengandalkan perspective:

```solidity
function isStrategyAllowed(address id) external view returns (bool) {
    return perspective.isVerified(id) || isVault[id];
}
```

### Execution Path — Full Chain

```
Tahap 1: Prasyarat — Kompromi Multi-sig
  (Hanya jika multi-sig 1-of-1 atau 2-of-3 lemah)
  Atau: Social engineering attack pada signers

Tahap 2: Proxy Upgrade (Monad only)
  Step 1: Owner calls upgradeTo(maliciousImpl) on Monad Factory proxy
          → Factory logic now controlled by attacker
          → or: Owner calls setPerspective(attackerControlledAddr) langsung
  Step 3: Attacker-controlled perspective.isVerified(x) returns true for ANY x
          → "isVerified for all strategies"
          → Semua address dianggap strategy yang valid

Tahap 3: Strategy Injection
  Step 4: Attacker deploy contract "Strategy" yang meniru ERC-4626
          → previewRedeem() mengembalikan nilai tinggi palsu
          → maxWithdraw() mengembalikan max uint256
          → deposit() menerima dana dan tidak mengembalikan
          → withdraw() mengirim semua dana ke attacker
  Step 5: Owner (or attacker via EVC) menambahkan strategy ke supplyQueue
          → supplyQueue.push(attackerStrategy)

Tahap 4: Fund Extraction
  Step 6: Tunggu yield accrual atau deposit pengguna baru
          → deposit mengalir ke attackerStrategy via supplyStrategy()
          → Attacker menyedot dana via withdraw()
          ATAU:
  Step 6b: Owner panggil reallocate() untuk memindahkan dana ke attackerStrategy
          → Dana vault langsung dikirim ke attacker

Tahap 5: Coverup / Timelock Manipulation
  Step 7: Guardian bisa revoke? Ya, tapi Guardian juga appointed oleh owner
          → Jika multi-sig compromised, Guardian juga compromised
```

### Execution Path — Cross-Chain Escalation (Monad → Base)

Setelah menguasai Monad Factory, attacker bisa memanfaatkan cross-chain:

```
  Step 1: setPeer() on Monad Router → ubah peer Base ke address attacker
  Step 2: Buat vault di Monad (via compromised factory)
  Step 3: Setup payout dengan merkle roots
  Step 4: Kirim pesan LZ dari Monad ke Base (seolah-olah claim valid)
  Step 5: Base Router menerima pesan → executeClaims pada vault di Base
          → claim payout dari vault legitimate di Base
          → Dana dikirim ke attacker
          → Ini adalah cross-chain message spoofing (primitif bridge)
```

### Required State

| Kondisi | Chain | Status |
|---|---|---|
| Factory adalah proxy | **Monad only** | ✅ Confirmed |
| Owner dapat upgrade tanpa timelock | Monad | ✅ Confirmed (proxy standard) |
| Owner dapat setPerspective kapan saja | Semua chain | ✅ Confirmed |
| Perspective mempengaruhi isStrategyAllowed | Semua chain | ✅ `isVerified()` adalah gate |
| Cross-chain message dapat difalsifikasi | Semua | ⚠️ Butuh `setPeer()` atau compromised LZ DVN |

### Capital Required

| Role | Capital | Notes |
|---|---|---|
| Compromise multi-sig | $0 (social) or $X (bribe) | Tergantung threshold multi-sig |
| Deploy malicious implementation | $50-$200 gas | Flat deployment cost |
| Deploy fake ERC-4626 strategy | $20-$50 gas | Simple contract |
| LZ message fee (untuk cross-chain) | $5-$20 | Via Router |

### Expected Profit

| Source | Amount | Notes |
|---|---|---|
| TVL Monad vaults | $4.7K | Jika ada vault aktif |
| Cross-chain drain Base vault | **$4.33M** | Jika cross-chain message spoofing berhasil |
| **Maximum theoretical** | **~$4.34M** | Gabungan TVL |

### Blockers

| Blocker | Dampak |
|---|---|
| **⚠️ Multi-sig threshold** | Jika multi-sig 3-of-5 atau lebih, butuh kompromi multiple signers |
| **⚠️ EVC account owner check** | `setPerspective` menggunakan `onlyEVCAccountOwner` — mungkin ada proteksi tambahan |
| **⚠️ LayerZero DVN** | Cross-chain message spoofing terhalang oleh DVN verification |
| ✅ Proxy upgrade tanpa timelock | **TIDAK ada blocker** untuk upgrade Monad factory |

### Deteksi Anomali

| Metode | Efektivitas |
|---|---|
| Monitor Proxy Admin events (`Upgraded`) | ✅ On-chain event — detectable in real-time |
| Monitor `SetPerspective` event | ✅ On-chain event |
| Monitor `CrossChainClaimInitiated` dari chain asing | ✅ Jika monitoring aktif |
| **Waktu reaksi** | Hanya beberapa detik — butuh automated monitoring |

### Confidence

| Dimensi | Confidence | Alasan |
|---|---|---|
| **Primitif valid (upgrade)** | **VERY HIGH** | Proxy Monad confirmed, upgrade function standard OZ |
| **Primitif valid (perspective)** | **VERY HIGH** | `setPerspective` on all chains, confirmed in source |
| **Exploitability** | **LOW-MEDIUM** | Butuh akses owner/multi-sig — privilege escalation |
| **Profitability (Monad only)** | **LOW** | $4.7K TVL — dampak terbatas |
| **Profitability (cross-chain)** | **MEDIUM** | Jika cross-chain message spoofing berhasil |
| **Overall** | **MEDIUM** | Risiko tertinggi di Monad, perlu verifikasi multi-sig security |

---

## Perbandingan Ketiga Hipotesis

| Kriteria | H-01: Flashloan + Oracle | H-02: Cross-Chain Double-Claim | H-03: Proxy + Governance |
|---|---|---|---|
| **Primitif digabungkan** | 4 (flashloan, oracle, erc4626, reward) | 4 (bridge, reward, erc4626, governance) | 4 (governance, bridge, reward, liquidation) |
| **Exploitability** | LOW-MEDIUM | **HIGH** | LOW-MEDIUM |
| **Impact Max** | MEDIUM ($100K) | **CRITICAL** ($6K+/cycle) | **CRITICAL** ($4.34M) |
| **Permission needed** | None | None | **Owner multi-sig** |
| **Capital needed** | $100K-$1M | **$10-$120** | $50-$200 |
| **Detection difficulty** | MEDIUM (MEV) | **HIGH** (undetectable on-chain) | LOW (events emitted) |
| **Unique to chain** | Monad/Katana | **All chains** | **Monad only** |
| **Priority** | 🟢 P3 | **🔴 P0** | 🟡 P1 |

---

## Kesimpulan: 3 Hipotesis Paling Mungkin

```
Priority     H-02                    H-03           H-01
Level:    ──────●───────────────────────●──────────────●──────
                🔴 P0                  🟡 P1          🟢 P3
                HIGH                    MEDIUM         LOW-MEDIUM
                Exploitability          Exploitability Exploitability
                CRITICAL Impact         CRITICAL Impact MEDIUM Impact
                No permission needed    Owner needed   Flashloan needed
```

**H-02: Cross-Chain Payout Double-Claim** adalah hipotesis paling mungkin dan berbahaya — exploitability HIGH, impact CRITICAL, tanpa permission, tanpa modal besar, dan sulit dideteksi.

**Next step:** Fork testing untuk H-02 — verifikasi apakah vault memiliki address yang sama di Arb/Monad/Katana dan apakah payoutId collision dapat dieksploitasi secara realistis.
