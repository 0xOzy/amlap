# Tugas Lanjutan Analisis Ample Earn

Kamu adalah asisten riset keamanan smart contract yang bekerja dalam framework `ai-sec-research`. Patuhi selalu SYSTEM/core_identity.md, SYSTEM/anti_hallucination.md, dan SYSTEM/exploit_validation.md.

## Konteks Target
- Target: Ample Earn (HackenProof)
- Deskripsi: Prize-linked savings protocol di atas Euler Earn.
- Kontrak utama: AmplePerspective, AmpleEarnFactory, AmpleEarnCrossChainRouter (deployed di Base, Arbitrum, Monad, Katana).

## File yang Harus Kamu Baca dan Pahami
1. Laporan temuan yang sudah divalidasi:
   - TARGETS/ample_earn/findings/drafts/AE-F-002_CrossChainPayoutReplay.md
   - TARGETS/ample_earn/findings/drafts/AE-F-005_ReentrancyGap.md
2. Ringkasan temuan tervalidasi:
   - TARGETS/ample_earn/research/VALIDATED_FINDINGS.md
3. Prioritas fork test:
   - TARGETS/ample_earn/research/FORK_TEST_PRIORITY.md
4. Status false positives:
   - TARGETS/ample_earn/research/FALSE_POSITIVES.md
5. Perbandingan kasus historis:
   - TARGETS/ample_earn/research/HISTORICAL_MATCHES.md
6. File riset lain yang relevan:
   - TARGETS/ample_earn/research/EXPLOIT_STEPS.md
   - TARGETS/ample_earn/research/HYPOTHESES.md
   - TARGETS/ample_earn/research/ECONOMIC_CEILING.md
   - TARGETS/ample_earn/research/TRUST_ASSUMPTIONS_MATRIX.md
   - TARGETS/ample_earn/research/STATE_MACHINE.md
7. Laporan submission HackenProof (draft final):
   - TARGETS/ample_earn/findings/drafts/submission_AE-F-002.md
   - TARGETS/ample_earn/findings/drafts/submission_AE-F-005.md
8. Semua file kode sumber target di `TARGETS/ample_earn/source/` (Base, Arbitrum, Monad, Katana).
9. Hasil fork test dan PoC:
   - src/test/FT-02_CrossChainPayoutReplay.t.sol
   - src/test/FT-02_FullPoC.t.sol
   - src/test/FT-05_ReentrancyPoC.sol

## Tugas
1. Review semua temuan yang sudah divalidasi (AE-F-002 dan AE-F-005) dengan membandingkan pola serangan di HISTORICAL_MATCHES.md. Identifikasi apakah ada aspek yang belum tercakup dalam laporan submission.
2. Periksa apakah masih ada pertanyaan yang belum terjawab di FORK_TEST_PRIORITY.md, terutama tentang Merkle root, leaf encoding, dan payoutId coordination.
3. Lakukan analisis lanjutan terhadap potensi dampak cross-chain replay jika dikombinasikan dengan temuan reentrancy (AE-F-005), dengan merujuk pada pola serangan historis yang mirip.
4. Evaluasi kembali apakah ada temuan lain yang sebelumnya dianggap false positive tetapi mungkin valid setelah pengujian lebih dalam, dengan membandingkan ke kasus-kasus di HISTORICAL_MATCHES.md.
5. Siapkan daftar rekomendasi perbaikan tambahan untuk tim Ample yang mencakup mitigasi jangka panjang, belajar dari bagaimana kasus serupa ditangani di masa lalu.
6. Jika ada data on-chain tambahan yang bisa memperkuat laporan (misalnya event log, storage layout), sarankan cara mengambilnya menggunakan Foundry (`cast`).
7. Periksa apakah laporan submission sudah memenuhi standar HackenProof: kejelasan, kelengkapan, dan adanya PoC yang bisa direproduksi. Beri saran untuk menyertakan referensi ke insiden historis yang relevan.
8. Berikan opini tentang kemungkinan severity upgrade/downgrade setelah mempertimbangkan semua faktor, termasuk signifikansi insiden serupa di masa lalu (contoh: Nomad $190M, Kelp DAO $292M).

## Output
Simpan hasil analisis dalam file baru:
- TARGETS/ample_earn/research/POST_VALIDATION_ANALYSIS.md

10. Dataset eksternal untuk referensi kerentanan:
   - DATASETS/smart_contracts/vulnerable/smartbugs-curated
   - DATASETS/smart_contracts/swc-registry
   - DATASETS/smart_contracts/vulndb
