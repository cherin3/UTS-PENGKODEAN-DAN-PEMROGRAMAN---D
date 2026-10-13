# Log Prompt AI — UTS Pemrograman / Coding Akuntansi

Nama: Cherin Amelia | NIM: 12030124130128 | Kelas: D

## 1. Gemini Canvas (Soal 3.1a — formulir voucher)

**Prompt 1:**
> “Buatkan satu file HTML mandiri berisi form Voucher Kas Keluar untuk akuntansi: header (tanggal, nomor bukti, deskripsi, pembuat) dan tabel baris jurnal dinamis (akun, debit, kredit) dengan tombol tambah/hapus baris. Dropdown akun dari array JavaScript.”
“Tambahkan total debit, total kredit, dan selisih yang terhitung otomatis setiap input berubah, plus indikator hijau ‘SEIMBANG’ atau merah ‘TIDAK SEIMBANG — selisih X’.”
“Tombol Submit harus disabled kecuali debit = kredit, total > 0, minimal 2 baris terisi, setiap baris bernominal punya akun. Hitung dalam satuan sen (integer) supaya tidak ada galat floating point.”
“Saat Submit, kirim POST ke /rest/v1/rpc/create_voucher Supabase dengan body p_date, p_ref, p_desc, p_user, p_lines (array akun/debit/kredit). Jika URL kosong, tampilkan payload JSON.”
“Dukungan dark mode, responsif di layar HP, dan pesan validasi yang menjelaskan mengapa Submit belum aktif.” 


**Ringkasan hasil:** html voucher kas keluar


## 2. NotebookLM (Soal 3.1b — verifikasi PSAK)

**Sumber yang diunggah:** PSAK 1, PSAK 2, ...

**Pertanyaan 1:**
> Berdasarkan dokumen yang saya upload (kode SQL dan standar PSAK), tolong analisis:
  Apakah trigger fn_check_journal_balance sudah memenuhi prinsip double-entry system sesuai PSAK 1?
  Apakah mekanisme immutability (status POSTED yang tidak dapat di-UPDATE/DELETE) sudah sesuai dengan prinsip audit trail dalam standar akuntansi?
  Apakah penggunaan hash SHA-256 pada hash_checksum sudah memenuhi kebutuhan verifikasi integritas data akuntansi?
  Apakah klasifikasi akun BALANCE_SHEET dan INCOME_STATEMENT sudah sesuai dengan PSAK 1 tentang Penyajian Laporan Keuangan?
  Apakah pengakuan kas pada akun 1-1100 sudah sesuai dengan definisi kas dan setara kas dalam PSAK 2?
  Berikan jawaban dengan menyertakan kutipan dari dokumen yang relevan.

**Ringkasan jawaban:** sesuai dengan lembar jawaban

## 3. Claude (bantuan penjelasan dan pengecekan kode)

- Digunakan untuk: membantu menyusun skema SQL, trigger, dan menjelaskan konsep
- Seluruh kode saya jalankan dan uji sendiri di Supabase/PostgreSQL.
