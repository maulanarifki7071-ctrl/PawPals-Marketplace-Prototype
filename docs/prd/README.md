# Product requirements — v3.0
Dokumen utama: [PRD Word v3.0](PawPals_PRD_v3.0_Premium_UIUX_2026-11-20.docx), 20 November 2026. Salinan dipertahankan dari PRD Premium yang terakhir disusun.

**Tujuan:** mempertemukan pemilik hewan dengan mitra pet care, mengurangi friksi pencarian dan reservasi, memungkinkan mitra mengelola jadwal dan pendapatan, serta menyediakan pengawasan administratif yang dapat diaudit.

| Aktor | Kebutuhan inti | Ukuran keberhasilan (kriteria, bukan hasil pengukuran) |
|---|---|---|
| Customer | Katalog, hewan, slot, checkout, pesanan, chat, review, bantuan | Memesan tanpa overbooking; status dan langkah berikutnya jelas |
| Vendor | Verifikasi, lokasi, layanan, paket, agenda, kapasitas, pengerjaan, finance | Jadwal dan tindakan sesuai status; data transaksi konsisten |
| Admin | Verifikasi, operasi, finance, trust & safety, RBAC | Tindakan sesuai permission, dapat ditelusuri |

Satu booking satu hewan/paket; Instant Booking; harga IDR positif; pembayaran dan payout tidak diklaim live. Di luar scope: multi-pet checkout, dynamic pricing, microservices, GPS langsung, social chat, otomasi KYC penuh. Galeri layanan aktual, analytics agregat, persistent notification dan password recovery UI belum lengkap.

Acceptance release: seluruh P0 ditutup, alur E2E dan build lulus, private media terlindungi, ledger konsisten, UX tidak membingungkan, dokumentasi sinkron. Lihat bagian Validation dan Current limitations pada [README utama](../../README.md).
