# Verifikasi Merkle Root On-Chain - Metode Langsung (cast call)

Kamu adalah asisten riset dalam framework `ai-sec-research`. Gunakan Foundry `cast` untuk memverifikasi on-chain apakah Merkle root untuk payoutId yang sama identik di beberapa chain (Base, Arbitrum, Monad, Katana).

## Langkah Wajib (Harus Diikuti Berurutan)

### 1. Temukan Vault Address

- Base: Factory `0x62b304519ee30e205621920454c2802fb99dca67`
- Arbitrum: Factory `0x9881464adE08EaEa838d1ba06073A0c8F972B185`
- Monad: Factory `0x9881464adE08EaEa838d1ba06073A0c8F972B185`
- Katana: Factory `0x9881464adE08EaEa838d1ba06073A0c8F972B185`

Jalankan perintah ini untuk setiap chain (jangan hitung slot manual, gunakan fungsi publik):

# Coba baca perspective() dari factory untuk dapat vault address
cast call <FACTORY_ADDRESS> "perspective()(address)" --rpc-url $BASE_RPC_URL

Catatan:
- Jika gagal (revert), catat "vault tidak ditemukan" dan lanjut ke chain berikutnya.
- JANGAN gunakan cast storage untuk mencari vault.

## 2. Baca PayoutPool Langsung via Fungsi Publik

Untuk setiap vault yang ditemukan, jalankan:

# Cek currentPayoutId
cast call <VAULT_ADDRESS> "currentPayoutId()(uint256)" --rpc-url $CHAIN_RPC_URL

# Baca payoutPool untuk payoutId=0 (atau yang tersedia)
cast call <VAULT_ADDRESS> "payoutPool(uint256)(bool,uint8,uint8,uint256,uint256,uint256,uint256,bytes32,bytes32)" 0 --rpc-url $CHAIN_RPC_URL

Catatan:

- Tipe data struct PayoutPool sudah terverifikasi dari source code IAmpleEarn.sol.
- Parameter ke-8 (bytes32) adalah participantsRoot
- Parameter ke-9 (bytes32) adalah designatedRecipientsRoot
- JANGAN hitung slot secara manual.
- Gunakan cast call langsung ke fungsi publik.

## 3. Bandingkan Merkle Root

- Ekstrak participantsRoot (bytes32 ke-8) dan designatedRecipientsRoot (bytes32 ke-9) dari output.
- Bandingkan nilai-nilai ini untuk payoutId yang sama di chain yang berbeda.
- Jika nilainya sama → Merkle root global → replay PASTI MUNGKIN.
- Jika berbeda → per-chain root → replay masih mungkin jika leaf tidak chain-specific.
- Jika 0x000... → payout belum diinisialisasi → tidak mengurangi validitas temuan.

## 4. Simpan Hasil

Tulis semua output ke:
TARGETS/ample_earn/research/ONCHAIN_MERKLE_VERIFICATION.md

Dengan format:

- Tabel hasil per chain:
  - vault address
  - payoutId
  - participantsRoot
  - designatedRecipientsRoot
- Kesimpulan:
  - apakah root identik
  - tidak identik
  - atau tidak dapat diverifikasi
- Dampak terhadap severity AE-F-002

## Environment

- RPC:
  - $BASE_RPC_URL
  - $ARB_RPC_URL
  - $MONAD_RPC_URL
  - $KATANA_RPC_URL

- Tools:
  - Foundry cast

## ATURAN PENTING

1. JANGAN gunakan cast storage untuk menghitung slot mapping.
2. JANGAN gunakan aritmatika heksadesimal (printf, bc) untuk offset slot.
3. GUNAKAN cast call ke fungsi publik kontrak (ABI sudah tersedia dari source code).
4. Jika fungsi revert atau vault tidak ditemukan, catat dan lanjutkan.

