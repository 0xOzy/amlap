# Historical Comparisons — Ample Earn

## AE-F-002: Cross-Chain Payout Replay

### 1. Sherlock Lend — LayerZero Cross-Chain Borrow Replay (2025)
- **Platform:** Sherlock Audit Contest (Lend Protocol)
- **Kerugian:** Unlimited token inflation (potensial)
- **Root Cause:** `CrossChainRouter` memproses pesan `BorrowCrossChain` via LayerZero tanpa replay protection (tidak ada nonce, GUID, atau mapping "processed message").
- **Kesamaan:** Mekanisme cross-chain replay persis — tidak ada chain ID atau identifier unik dalam payload.
- **Tingkat Kemiripan:** 95%
- **Referensi:** Sherlock Audit Report #517

### 2. Nomad Bridge Hack (Agustus 2022) — $190M
- **Kerugian:** $190M+
- **Root Cause:** Update rutin membuat verifikasi pesan bypass — `0x00` dianggap root valid. Siapapun bisa copy-paste transaksi sah dan mengganti alamat penerima.
- **Kesamaan:** Pola "copy valid proof → replace recipient → replay di chain lain".
- **Tingkat Kemiripan:** 80%
- **Referensi:** Rekt News, samczsun postmortem

### 3. Intent Bridge — Cross-Domain Replay (Cantina Blog)
- **Root Cause:** EIP-712 domain separator tidak menyertakan `chainId`. Solver jahat mereplay signed intent di chain lain.
- **Kesamaan:** Data valid di chain A juga valid di chain B karena tidak ada chain context.
- **Tingkat Kemiripan:** 90%
- **Referensi:** Cantina Blog - Cross-Domain Replay

### 4. CREATE2 Cross-Chain Replay Warning (Code4rena)
- **Warning:** CREATE2 salt sama → alamat kontrak identik di semua chain. Risiko replay deposit.
- **Relevansi:** Ample Earn menggunakan CREATE2 dengan salt sama di Arbitrum, Monad, Katana — precondition utama AE-F-002.
- **Referensi:** Code4rena Findings Database

### 5. Kelp DAO — $292M LayerZero Forged Message (April 2026)
- **Kerugian:** $292M (exploit DeFi terbesar 2026)
- **Root Cause:** Konfigurasi DVN 1-of-1 tanpa optional verifier — penyerang memalsukan cross-chain message. Mainnet bridge melepas 116,500 rsETH.
- **Kesamaan:** LayerZero sebagai attack surface yang sama — kerentanan fundamental pada cross-chain message validation.
- **Tingkat Kemiripan:** 70% (mekanisme berbeda, dampak serupa)
- **Referensi:** LayerZero Postmortem, Rekt News

---

## AE-F-005: Missing `nonReentrant` Modifier

### 6. rsETH Reentrancy Exploit — $4.2M
- **Kerugian:** ~$4.2M
- **Root Cause:** Fungsi klaim reward hilang modifier `nonReentrant`. Update saldo reward sebelum transfer token — CEI pattern dilanggar.
- **Kesamaan:** Identik: hilangnya `nonReentrant` pada fungsi yang update state lalu transfer ETH.
- **Tingkat Kemiripan:** 95%
- **Referensi:** Immunefi, Rekt News

### 7. BorrowerOperations flashLoan Reentrancy (Immunefi)
- **Root Cause:** Fungsi `flashLoan()` tanpa `nonReentrant` memungkinkan unlimited borrow via callback `onFlashLoan`.
- **Relevansi:** Missing `nonReentrant` pada fungsi batch/external-call-heavy adalah bug yang sering ditemukan.
- **Referensi:** Immunefi Reports

### 8. XDeFi Merge Reentrancy (Code4rena)
- **Root Cause:** Fungsi `merge()` tidak memiliki `nonReentrant` modifier — attacker re-enter untuk memanipulasi state.
- **Referensi:** Code4rena Audit Report

---

## Pola Kombinasi: Cross-Chain + Reentrancy

### 9. Double-Claim via Batched Yield Distribution (Immunefi)
- **Root Cause:** Tidak ada snapshot point-in-time untuk batch yield distribution. Token bisa ditransfer antar indeks antar batch → double-claim.
- **Relevansi:** Double-claim lewat manipulasi index + timing — analog ke kombinasi replay + reentrancy (dua vektor berbeda, dampak sama: dana diklaim dua kali).
- **Referensi:** Immunefi Blog

---

## Lesson Learned & Relevansi ke Ample Earn

1. **Cross-chain replay adalah bug klasik senilai ratusan juta dolar.** Nomad, Wormhole, Sherlock → data valid di satu chain tidak boleh otomatis valid di chain lain tanpa chain context.
2. **Missing `nonReentrant` tetap jadi low-hanging fruit yang mematikan.** rsETH ($4.2M) bukti terbaru bahwa fungsi update-state + transfer wajib dilindungi.
3. **LayerZero adalah attack surface yang sedang panas.** Kelp DAO ($292M) menunjukkan konfigurasi validator lemah bisa katastropik. Ample Earn gunakan LayerZero di CrossChainRouter → amplification factor.
4. **CREATE2 + same salt = deterministik address = replay precondition.** Diperingatkan komunitas audit sejak 2023.
5. **Kombinasi dua bug (replay + reentrancy) belum ada preseden publik** — potensi temuan langka jika berhasil dibuktikan.
