--------------------------------------------------------------------------------
-- PROYEK  : Customer Support Ticket Analytics
-- TAHAP 3 : Pemodelan dimensional (star schema)
-- TARGET  : PostgreSQL 17, database ticket_analytics
-- CATATAN : Jalankan seluruh berkas ini sekali di pgAdmin Query Tool.
--           Tabel hasil di bawah inilah yang nanti dibaca Power BI,
--           bukan tabel tickets maupun stg_tickets.
--------------------------------------------------------------------------------

DROP TABLE IF EXISTS fact_ticket;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_priority;
DROP TABLE IF EXISTS dim_status;
DROP TABLE IF EXISTS dim_sla;
DROP TABLE IF EXISTS dim_issue;
DROP TABLE IF EXISTS dim_product;

--------------------------------------------------------------------------------
-- 1. DIMENSI TANGGAL
-- Dibuat sendiri, bukan diambil dari sumber. Rentangnya sengaja dilebihkan
-- sampai Januari 2026 karena sebagian tiket ditutup setelah Desember 2025.
--------------------------------------------------------------------------------

CREATE TABLE dim_date AS
SELECT d::date                                AS tanggal,
       EXTRACT(YEAR    FROM d)::int           AS tahun,
       EXTRACT(QUARTER FROM d)::int           AS kuartal,
       EXTRACT(MONTH   FROM d)::int           AS bulan_angka,
       TO_CHAR(d, 'YYYY-MM')                  AS tahun_bulan,
       TRIM(TO_CHAR(d, 'Month'))              AS nama_bulan,
       DATE_TRUNC('month', d)::date           AS awal_bulan
FROM generate_series(DATE '2022-01-01', DATE '2026-01-31', INTERVAL '1 day') d;

ALTER TABLE dim_date ADD PRIMARY KEY (tanggal);

--------------------------------------------------------------------------------
-- 2. DIMENSI PRIORITAS
-- Kolom urutan dipakai Power BI untuk mengurutkan sumbu grafik secara benar.
-- Tanpa ini, Power BI mengurutkan menurut abjad: high, low, medium, urgent.
--------------------------------------------------------------------------------

CREATE TABLE dim_priority (
    priority VARCHAR(20) PRIMARY KEY,
    urutan   INT
);
INSERT INTO dim_priority VALUES
    ('urgent', 1), ('high', 2), ('medium', 3), ('low', 4);

--------------------------------------------------------------------------------
-- 3. DIMENSI STATUS
-- Kolom kelompok adalah atribut turunan yang menjadi inti analisis:
-- pemisahan antara tiket selesai, tiket terbengkalai, dan tiket menggantung.
--------------------------------------------------------------------------------

CREATE TABLE dim_status (
    status   VARCHAR(50) PRIMARY KEY,
    kelompok VARCHAR(30),
    urutan   INT
);
INSERT INTO dim_status VALUES
    ('resolved',         'Selesai',       1),
    ('closed_no_action', 'Terbengkalai',  2),
    ('in_progress',      'Belum selesai', 3),
    ('on_hold',          'Belum selesai', 4),
    ('open',             'Belum selesai', 5);

--------------------------------------------------------------------------------
-- 4. DIMENSI PAKET SLA
--------------------------------------------------------------------------------

CREATE TABLE dim_sla (
    sla_plan VARCHAR(20) PRIMARY KEY,
    urutan   INT
);
INSERT INTO dim_sla VALUES
    ('platinum', 1), ('gold', 2), ('standard', 3);

--------------------------------------------------------------------------------
-- 5. DIMENSI JENIS MASALAH DAN AREA PRODUK
--------------------------------------------------------------------------------

CREATE TABLE dim_issue AS
SELECT DISTINCT issue_type FROM tickets WHERE issue_type IS NOT NULL;
ALTER TABLE dim_issue ADD PRIMARY KEY (issue_type);

CREATE TABLE dim_product AS
SELECT DISTINCT product_area FROM tickets WHERE product_area IS NOT NULL;
ALTER TABLE dim_product ADD PRIMARY KEY (product_area);

--------------------------------------------------------------------------------
-- 6. TABEL FAKTA
-- Tanggal acuan 30 Desember 2025 adalah tanggal tiket terakhir pada dataset,
-- dipakai sebagai titik potret untuk menghitung umur tiket yang belum selesai.
--------------------------------------------------------------------------------

CREATE TABLE fact_ticket AS
SELECT
    t.ticket_id,
    t.created_at,
    t.created_at::date AS tanggal_dibuat,

    CASE WHEN t.resolution_time_raw IS NOT NULL
         THEN (t.created_at + (t.resolution_time_raw || ' hours')::interval)::date
    END AS tanggal_tutup,

    t.priority,
    t.status,
    t.sla_plan,
    t.issue_type,
    t.product_area,
    t.channel,
    t.platform,
    t.region,
    t.customer_segment,
    t.customer_id,

    t.resolution_time_raw AS durasi_jam,

    CASE WHEN t.status = 'resolved'         THEN t.resolution_time_raw END AS durasi_selesai_jam,
    CASE WHEN t.status = 'closed_no_action' THEN t.resolution_time_raw END AS durasi_terbengkalai_jam,

    CASE WHEN t.resolution_time_raw IS NULL
         THEN (DATE '2025-12-30' - t.created_at::date)
    END AS umur_hari,

    CASE WHEN t.resolution_time_raw IS NULL THEN
        CASE WHEN (DATE '2025-12-30' - t.created_at::date) <= 30  THEN 'a. sampai 30 hari'
             WHEN (DATE '2025-12-30' - t.created_at::date) <= 90  THEN 'b. 31-90 hari'
             WHEN (DATE '2025-12-30' - t.created_at::date) <= 365 THEN 'c. 91-365 hari'
             ELSE 'd. lebih dari 1 tahun'
        END
    END AS kelompok_umur,

    CASE WHEN t.status = 'resolved' THEN
        CASE WHEN t.resolution_time_raw <= 8  THEN 'a. sampai 8 jam'
             WHEN t.resolution_time_raw <= 24 THEN 'b. 8-24 jam'
             WHEN t.resolution_time_raw <= 48 THEN 'c. 24-48 jam'
             ELSE 'd. di atas 48 jam'
        END
    END AS kelompok_durasi,

    CASE WHEN t.status = 'resolved' AND t.resolution_time_raw > 106.9 THEN 1 ELSE 0 END AS flag_lama,
    CASE WHEN t.resolution_time_raw IS NULL THEN 1 ELSE 0 END AS flag_belum_selesai,

    t.reopened,
    t.has_attachment,
    t.csat_score,
    NULLIF(t.csat_score, 0) AS csat_dinilai,
    t.customer_sentiment
FROM tickets t;

ALTER TABLE fact_ticket ADD PRIMARY KEY (ticket_id);

CREATE INDEX idx_fact_tanggal   ON fact_ticket (tanggal_dibuat);
CREATE INDEX idx_fact_status    ON fact_ticket (status);
CREATE INDEX idx_fact_priority  ON fact_ticket (priority);

--------------------------------------------------------------------------------
-- 7. VERIFIKASI
--------------------------------------------------------------------------------

-- Harus 100.000
SELECT COUNT(*) AS baris_fakta FROM fact_ticket;

-- Harus cocok dengan temuan: 29.756 tiket berumur lebih dari satu tahun
SELECT kelompok_umur, COUNT(*)
FROM fact_ticket
WHERE kelompok_umur IS NOT NULL
GROUP BY kelompok_umur
ORDER BY kelompok_umur;

-- Harus 6.103 bernilai nol, karena seluruh tiket selesai berada di bawah ambang
SELECT SUM(flag_lama) AS tiket_selesai_di_atas_ambang FROM fact_ticket;
