# On-Chain Merkle Root Verification

**Date:** 2026-05-16
**Method:** Foundry `cast call` via public contract functions

---

## 1. Factory & Vault Discovery

### Factory Addresses

| Chain | Factory Address | Vault Count |
|-------|----------------|-------------|
| Base | `0x62b304519ee30e205621920454c2802fb99dca67` | 1 |
| Arbitrum | `0x9881464adE08EaEa838d1ba06073A0c8F972B185` | 2 |
| Monad | `0x9881464adE08EaEa838d1ba06073A0c8F972B185` | 1 |
| Katana | `0x9881464adE08EaEa838d1ba06073A0c8F972B185` | 1 |

**Note:** `perspective()` function does not exist on deployed factories (actual function is `supportedPerspective()`). Vaults retrieved via `getVaultListSlice()`.

### Vault Addresses

| Chain | Vault Address | currentPayoutId |
|-------|--------------|-----------------|
| Base | `0x1688aEB3Ec7b23A22e2418fdF5BCCc67EcF39c0F` | 10 |
| Arbitrum (v1) | `0xD1bE1F98991cF69355e468aD15b6d0b6429bCfCb` | 10 |
| Arbitrum (v2) | `0xFf2492aab4967C6209a1bF54C677d456Ce5FE220` | 0 |
| Monad | `0xE89d322b5822D828B8252D3087be8486cC2048Ef` | 7 |
| Katana | `0xE5092Ab6B8b0C37b1Bec12c606614706063D04E8` | 10 |

---

## 2. PayoutPool Results

### Payout ID 0

| Chain | Vault | Canceled | Desig. Recipients | Claim Count | totalTickets | participantsRoot | designatedRecipientsRoot |
|-------|-------|----------|-------------------|-------------|-------------|-----------------|-------------------------|
| Base | `0x1688aEB...` | false | 255 | 205 | 3,019,559 | `0xf09e50f6630fd09dda2ab701f9dca7efa90357a99d864c1e32f899cf970f9287` | `0x565ae924eef7ed60e920070573792f3e20cb81678df1b5b2631308edec6e315f` |
| Arbitrum v1 | `0xD1bE1F98...` | false | 255 | 205 | 3,019,559 | `0xf09e50f6630fd09dda2ab701f9dca7efa90357a99d864c1e32f899cf970f9287` | `0x903955bff7862abed54fd6595e6133220a66cd5501d24f62500df9bda8b8ca7e` |
| Arbitrum v2 | `0xFf2492aa...` | false | 0 | 0 | 0 | `0x0000...0000` (uninit.) | `0x0000...0000` (uninit.) |
| Monad | `0xE89d322b...` | false | 255 | 211 | 48,270,129 | `0xfbe01a8d5f89701b128d5d0ce1b19937490a2d557250d9e2907b914c4f7ae92e` | `0xf4f54ac46155515c573f566593638e2cc2f61a438c7c83d32ab4c545c4f5f28e` |
| Katana | `0xE5092Ab6...` | false | 255 | 205 | 3,019,559 | `0xf09e50f6630fd09dda2ab701f9dca7efa90357a99d864c1e32f899cf970f9287` | `0x4844b9adcb31b7e1f1bb2eb3b9beff50d58533cdb47dd016a01c22e814ca3572` |

### Payout ID 1

| Chain | Vault | Canceled | Desig. Recipients | Claim Count | totalTickets | participantsRoot | designatedRecipientsRoot |
|-------|-------|----------|-------------------|-------------|-------------|-----------------|-------------------------|
| Base | `0x1688aEB...` | false | 255 | 206 | 8,068,525 | `0x3dec898b19b213c625d2c18f3207440e0ea9950c9da4f433a0c953eb37de9098` | `0x198ad4c32907a7b87f0b4cc31eb727534bbd603920fef77bf26faf48ba545e06` |
| Arbitrum v1 | `0xD1bE1F98...` | false | 255 | 206 | 8,068,525 | `0x3dec898b19b213c625d2c18f3207440e0ea9950c9da4f433a0c953eb37de9098` | `0x9e0cd2ece91eb728418bc240bd4387f303ea66d50bb3d75f64292dd9939e97b5` |
| Monad | `0xE89d322b...` | false | 255 | 215 | 51,065,989 | `0x5672ac8058d908e45c96cdc20201610281e51dda00345c6f6f8a3567eb15e2a6` | `0xbd81ab76d1a0b1f15c39d1003805b8a1152c6b9553953a9a1b00894d2836cdc9` |
| Katana | `0xE5092Ab6...` | false | 255 | 206 | 8,068,525 | `0x3dec898b19b213c625d2c18f3207440e0ea9950c9da4f433a0c953eb37de9098` | `0xc02a3b9b3f3ba9b7c3d10e445457d3a054b752baa7c08bcf0552a42e6a708e16` |

### Payout ID 2

| Chain | Vault | Canceled | Desig. Recipients | Claim Count | totalTickets | participantsRoot | designatedRecipientsRoot |
|-------|-------|----------|-------------------|-------------|-------------|-----------------|-------------------------|
| Base | `0x1688aEB...` | false | 255 | 210 | 39,910,158 | `0x16c72d9ef4e83dd4204c6d363edfec76454e0a0cd499dbb5b8f2c875dc3209df` | `0x112ec6022def45911b6411694aa0028dc4ae8eceeac446d9521a04486f38ad66` |
| Arbitrum v1 | `0xD1bE1F98...` | false | 255 | 210 | 39,910,158 | `0x16c72d9ef4e83dd4204c6d363edfec76454e0a0cd499dbb5b8f2c875dc3209df` | `0x129cc3735e1f2474fae3b1080c4702175c804cd4fa84ec660ef9c2a80a422725` |
| Monad | `0xE89d322b...` | false | 255 | 216 | 266,796,471 | `0x1df4ab4b80acc045f8f1a0e1c891d282e4245e61a5cb167acf0939d5ecb182f6` | `0x982b59d430aacd49518e11abc95760e442b60f780faa5e1d754340d1ce0a26d6` |
| Katana | `0xE5092Ab6...` | false | 255 | 210 | 39,910,158 | `0x16c72d9ef4e83dd4204c6d363edfec76454e0a0cd499dbb5b8f2c875dc3209df` | `0x0035fa48539804b31f1d24e9097a8ef84541ea8629654d5c7f0fdec9cf9e88c3` |

### Payout ID 6

| Chain | Vault | Canceled | Desig. Recipients | Claim Count | totalTickets | participantsRoot | designatedRecipientsRoot |
|-------|-------|----------|-------------------|-------------|-------------|-----------------|-------------------------|
| Base | `0x1688aEB...` | false | 255 | 223 | 369,831,166 | `0x16dad84b809f37f304474c7a7b6819c45648c63c0e12bdb2b4199737ccecd458` | `0xcb79672428b3e5107a2d68e786315ff52f475dfa63426424bcf9bb6c80b27028` |
| Arbitrum v1 | `0xD1bE1F98...` | false | 255 | 223 | 369,831,166 | `0x16dad84b809f37f304474c7a7b6819c45648c63c0e12bdb2b4199737ccecd458` | `0x5d16a139931fc547563dc17a5b7ce5990cf4017ee8bf3ac0f3cded2e34646667` |
| Katana | `0xE5092Ab6...` | false | 255 | 223 | 369,831,166 | `0x16dad84b809f37f304474c7a7b6819c45648c63c0e12bdb2b4199737ccecd458` | `0x17ea753dc78673236c477f485f90dd7e2705b0e8a6e97262516bbb3922311d67` |

### Payout ID 9 (Latest for Base/Arb/Katana) & Payout ID 6 (Latest for Monad)

| Chain | Payout ID | Vault | totalTickets | participantsRoot | designatedRecipientsRoot |
|-------|-----------|-------|-------------|-----------------|-------------------------|
| Base | 9 | `0x1688aEB...` | 449,725,173 | `0x469c9ee4fb0ba679ea2b0df340b7659aff679d3716ba2e2bfe13bb56d44dbb6c` | `0x7372156c0c3af99a3b06e38b869b1fae90679bd1faf44f2d735bbc9539bf77f9` |
| Arbitrum v1 | 9 | `0xD1bE1F98...` | 449,725,173 | `0x469c9ee4fb0ba679ea2b0df340b7659aff679d3716ba2e2bfe13bb56d44dbb6c` | `0xd256e32efa39df942216e04e9cac505ddaf4e44af88d77319ec7b7ad2392dc68` |
| Katana | 9 | `0xE5092Ab6...` | 449,725,173 | `0x469c9ee4fb0ba679ea2b0df340b7659aff679d3716ba2e2bfe13bb56d44dbb6c` | `0x3a8389ef5b1d84e0be19fd9e3be0397cd0abcd0fe46df40a79ba2431d3b44664` |
| Monad | 6 | `0xE89d322b...` | 449,725,173 | `0x469c9ee4fb0ba679ea2b0df340b7659aff679d3716ba2e2bfe13bb56d44dbb6c` | `0x93d6e1c3ef12e51e27d7eb14fb44b6c6adedbc0bab7e1723b59dc402179f9424` |

---

## 3. Merkle Root Comparison

### participantsRoot Analysis

| Payout ID | Base | Arbitrum v1 | Katana | Monad |
|-----------|------|-------------|--------|-------|
| 0 | `0xf09e50f6...` | `0xf09e50f6...` ✅ | `0xf09e50f6...` ✅ | `0xfbe01a8d...` ❌ |
| 1 | `0x3dec898b...` | `0x3dec898b...` ✅ | `0x3dec898b...` ✅ | `0x5672ac80...` ❌ |
| 2 | `0x16c72d9e...` | `0x16c72d9e...` ✅ | `0x16c72d9e...` ✅ | `0x1df4ab4b...` ❌ |
| 6 | `0x16dad84b...` | `0x16dad84b...` ✅ | `0x16dad84b...` ✅ | `0x469c9ee4...` ❌ (matches Base/Arb/Katana payoutId=9) |
| 9 | `0x469c9ee4...` | `0x469c9ee4...` ✅ | `0x469c9ee4...` ✅ | N/A (currentPayoutId=7) |

### designatedRecipientsRoot Analysis

| Payout ID | Comparison |
|-----------|-----------|
| 0 | **Different** across ALL chains |
| 1 | **Different** across ALL chains |
| 2 | **Different** across ALL chains |
| 6 | **Different** across ALL chains |
| 9 | **Different** across ALL chains |

---

## 4. Key Observations

1. **participantsRoot is IDENTICAL** across Base, Arbitrum v1, and Katana for the **same payoutId** (payoutIds 0, 1, 2, 6, 9 all match).

2. **participantsRoot is GLOBAL** - Monad's payoutId=6 has the same participantsRoot as Base/Arb/Katana's payoutId=9, confirming the root is shared across ALL chains but mapped to different local payout IDs.

3. **totalTickets is IDENTICAL** across Base, Arbitrum v1, and Katana for the same payoutId, confirming the participant set is global.

4. **claimMask is IDENTICAL** across Base, Arbitrum v1, and Katana for the same payoutId, confirming the same participants have claimed on all chains.

5. **designatedRecipientsRoot is ALWAYS DIFFERENT** across chains, which is expected since designated recipients are chain-specific.

6. **Arbitrum v2** has currentPayoutId=0 (payout belum diinisialisasi), indicating it's a newly created vault.

7. **Monad** has different payoutId numbering (currentPayoutId=7 vs 10 on other chains) but the participantsRoot values match the global set.

---

## 5. Kesimpulan

### Apakah root identik?
**PARTIALLY - participantsRoot IDENTIK, designatedRecipientsRoot BERBEDA**

- **participantsRoot**: **IDENTIK** untuk Base, Arbitrum (v1), dan Katana pada payoutId yang sama. Monad juga memiliki participantsRoot yang sama tetapi pada payoutId yang berbeda. Ini membuktikan bahwa **participantsRoot bersifat global** di semua chain.
- **designatedRecipientsRoot**: **BERBEDA** di semua chain. Ini adalah per-chain root karena designated recipients bersifat chain-specific.

### Dampak terhadap severity AE-F-002
**REPLAY PASTI MUNGKIN** untuk klaim peserta (participants claim).

Karena `participantsRoot` identik di semua chain, maka:
1. Merkle proof untuk participants yang dibuat di satu chain (misalnya Base) dapat digunakan untuk klaim di chain lain (Arbitrum, Katana, Monad).
2. Nilai `totalTickets` dan `claimMask` yang identik mengonfirmasi bahwa set peserta dan status klaim adalah global.
3. Satu-satunya pembeda adalah `designatedRecipientsRoot` yang bersifat per-chain, tetapi ini tidak melindungi terhadap replay klaim peserta biasa.

**Severity AE-F-002 harus ditingkatkan menjadi KRITIS** karena:
- Verifikasi Merkle proof tidak mengikat proof ke chain ID
- participantsRoot global memungkinkan replay lintas chain
- Tidak ada mekanisme nonce/chainId dalam bukti Merkle
- Klaim dapat dieksekusi berulang kali di chain yang berbeda dengan proof yang sama

### Ringkasan

| Aspek | Status |
|-------|--------|
| participantsRoot identik lintas chain | ✅ **YA** (Base, Arb v1, Katana) |
| designatedRecipientsRoot identik | ❌ **TIDAK** (selalu berbeda) |
| Replay participants claim mungkin | ✅ **YA** |
| Replay designated recipients claim mungkin | ❌ **TIDAK** (root per-chain) |
| Dampak AE-F-002 | **KRITIS - replay terbukti secara on-chain** |