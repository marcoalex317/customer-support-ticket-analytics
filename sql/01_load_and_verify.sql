--------------------------------------------------------------------------------
-- PROYEK  : Customer Support Ticket Analytics
-- TAHAP 1 : Pemuatan data dan verifikasi
-- SUMBER  : synthetic_it_support_tickets.csv (100.000 baris, 20 kolom)
-- TARGET  : PostgreSQL 17 (lokal)
-- CATATAN : Versi Oracle tersedia pada berkas 01_load_and_verify.sql
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- BAGIAN 1. TABEL STAGING
-- Semua kolom dibuat bertipe teks lebih dulu supaya proses muat tidak gagal
-- hanya karena satu baris bermasalah. Konversi tipe dilakukan setelahnya.
--------------------------------------------------------------------------------

CREATE TABLE stg_tickets (
    ticket_id             VARCHAR(50),
    created_at            VARCHAR(50),
    customer_id           VARCHAR(50),
    customer_segment      VARCHAR(50),
    channel               VARCHAR(50),
    product_area          VARCHAR(50),
    issue_type            VARCHAR(50),
    priority              VARCHAR(20),
    status                VARCHAR(50),
    sla_plan              VARCHAR(20),
    initial_message       VARCHAR(1000),
    agent_first_reply     VARCHAR(1000),
    resolution_summary    VARCHAR(1000),
    resolution_time_hours VARCHAR(50),
    reopened              VARCHAR(10),
    customer_sentiment    VARCHAR(30),
    csat_score            VARCHAR(10),
    has_attachment        VARCHAR(10),
    platform              VARCHAR(30),
    region                VARCHAR(20)
);

-- Muat CSV ke stg_tickets memakai Data Load pada Database Actions.
-- PENTING saat memuat:
--   1. Format tanggal kolom created_at adalah DD/MM/YYYY HH24:MI.
--   2. Nilai "NA" pada kolom region adalah North America, BUKAN nilai kosong.
--      Matikan opsi yang memperlakukan NA sebagai null.

--------------------------------------------------------------------------------
-- BAGIAN 2. TABEL BERTIPE
--------------------------------------------------------------------------------

CREATE TABLE tickets (
    ticket_id             VARCHAR(50) PRIMARY KEY,
    created_at            TIMESTAMP,
    customer_id           VARCHAR(50),
    customer_segment      VARCHAR(50),
    channel               VARCHAR(50),
    product_area          VARCHAR(50),
    issue_type            VARCHAR(50),
    priority              VARCHAR(20),
    status                VARCHAR(50),
    sla_plan              VARCHAR(20),
    has_initial_message   SMALLINT,
    has_first_reply       SMALLINT,
    has_resolution_summary SMALLINT,
    resolution_time_raw   NUMERIC,
    reopened              SMALLINT,
    customer_sentiment    VARCHAR(30),
    csat_score            NUMERIC,
    has_attachment        SMALLINT,
    platform              VARCHAR(30),
    region                VARCHAR(20)
);

INSERT INTO tickets
SELECT
    TRIM(ticket_id),
    TO_TIMESTAMP(created_at, 'DD/MM/YYYY HH24:MI'),
    TRIM(customer_id),
    TRIM(customer_segment),
    TRIM(channel),
    TRIM(product_area),
    TRIM(issue_type),
    TRIM(priority),
    TRIM(status),
    TRIM(sla_plan),
    CASE WHEN initial_message    IS NULL OR TRIM(initial_message)    = '' THEN 0 ELSE 1 END,
    CASE WHEN agent_first_reply  IS NULL OR TRIM(agent_first_reply)  = '' THEN 0 ELSE 1 END,
    CASE WHEN resolution_summary IS NULL OR TRIM(resolution_summary) = '' THEN 0 ELSE 1 END,
    NULLIF(TRIM(resolution_time_hours), '')::NUMERIC,
    NULLIF(TRIM(reopened), '')::SMALLINT,
    TRIM(customer_sentiment),
    NULLIF(TRIM(csat_score), '')::NUMERIC,
    NULLIF(TRIM(has_attachment), '')::SMALLINT,
    TRIM(platform),
    TRIM(region)
FROM stg_tickets;

COMMIT;

--------------------------------------------------------------------------------
-- BAGIAN 3. VERIFIKASI PEMUATAN
--------------------------------------------------------------------------------

-- 3.1 Jumlah baris harus 100.000 dan ticket_id harus unik
SELECT COUNT(*) AS jumlah_baris,
       COUNT(DISTINCT ticket_id) AS ticket_id_unik
FROM tickets;

-- 3.2 Rentang tanggal, untuk memastikan parsing tanggal tidak tertukar hari dan bulan
SELECT MIN(created_at) AS tanggal_awal,
       MAX(created_at) AS tanggal_akhir,
       COUNT(*) - COUNT(created_at) AS tanggal_gagal_parse
FROM tickets;

-- 3.3 Uji hari di atas 12. Jika hasilnya nol, berarti hari dan bulan tertukar.
SELECT COUNT(*) AS jumlah_tanggal_lebih_dari_12
FROM tickets
WHERE EXTRACT(DAY FROM created_at) > 12;

-- 3.4 Nilai unik setiap kolom kategorikal
SELECT 'status' AS kolom, status AS nilai, COUNT(*) AS jumlah FROM tickets GROUP BY status
UNION ALL SELECT 'priority', priority, COUNT(*) FROM tickets GROUP BY priority
UNION ALL SELECT 'sla_plan', sla_plan, COUNT(*) FROM tickets GROUP BY sla_plan
UNION ALL SELECT 'channel', channel, COUNT(*) FROM tickets GROUP BY channel
UNION ALL SELECT 'platform', platform, COUNT(*) FROM tickets GROUP BY platform
UNION ALL SELECT 'region', region, COUNT(*) FROM tickets GROUP BY region
UNION ALL SELECT 'product_area', product_area, COUNT(*) FROM tickets GROUP BY product_area
UNION ALL SELECT 'issue_type', issue_type, COUNT(*) FROM tickets GROUP BY issue_type
UNION ALL SELECT 'customer_segment', customer_segment, COUNT(*) FROM tickets GROUP BY customer_segment
UNION ALL SELECT 'customer_sentiment', customer_sentiment, COUNT(*) FROM tickets GROUP BY customer_sentiment
ORDER BY 1, 3 DESC;

-- 3.5 Pastikan region NA tidak hilang menjadi null
SELECT COUNT(*) AS region_kosong
FROM tickets
WHERE region IS NULL;

--------------------------------------------------------------------------------
-- BAGIAN 4. VERIFIKASI ULANG HASIL PROFILING
--------------------------------------------------------------------------------

-- 4.1 Nilai kosong resolution_time dikaitkan dengan status tiket
SELECT status,
       COUNT(*) AS jumlah_tiket,
       COUNT(resolution_time_raw) AS ada_nilai,
       COUNT(*) - COUNT(resolution_time_raw) AS kosong,
       ROUND((COUNT(*) - COUNT(resolution_time_raw)) * 100.0 / COUNT(*), 1) AS persen_kosong
FROM tickets
GROUP BY status
ORDER BY jumlah_tiket DESC;

-- 4.2 Sebaran csat_score per status, untuk menguji ulang apakah nilai nol
--     terdistribusi merata
SELECT status,
       COUNT(*) AS jumlah_tiket,
       SUM(CASE WHEN csat_score = 0 THEN 1 ELSE 0 END) AS csat_nol,
       ROUND(SUM(CASE WHEN csat_score = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS persen_nol
FROM tickets
GROUP BY status
ORDER BY jumlah_tiket DESC;

-- 4.3 Statistik resolution_time_raw. INI PEMERIKSAAN PALING PENTING.
--     Perhatikan besaran angkanya sebelum memutuskan satuan yang dipakai.
SELECT COUNT(resolution_time_raw) AS jumlah_terisi,
       MIN(resolution_time_raw) AS nilai_min,
       MAX(resolution_time_raw) AS nilai_maks,
       ROUND(AVG(resolution_time_raw), 1) AS rata_rata,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_time_raw)::NUMERIC, 1) AS median
FROM tickets;

-- 4.4 Kuartil dan ambang pencilan menurut metode IQR
SELECT q1,
       q3,
       q3 - q1 AS iqr,
       q3 + 1.5 * (q3 - q1) AS ambang_atas
FROM (
    SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY resolution_time_raw) AS q1,
           PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY resolution_time_raw) AS q3
    FROM tickets
    WHERE resolution_time_raw IS NOT NULL
);

-- 4.5 Jumlah tiket di atas ambang pencilan
--     Ganti angka 106.8 dengan hasil ambang_atas dari kueri 4.4
SELECT COUNT(*) AS tiket_di_atas_ambang
FROM tickets
WHERE resolution_time_raw > 106.8;

-- 4.6 Uji kewajaran satuan. Bandingkan hasil ketiga kolom di bawah ini
--     terhadap akal sehat operasional layanan pelanggan.
SELECT status,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_time_raw)::NUMERIC, 0) AS median_apa_adanya,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_time_raw) / 60)::NUMERIC, 1) AS jika_satuan_menit_jadi_jam,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_time_raw) / 1440)::NUMERIC, 1) AS jika_satuan_menit_jadi_hari
FROM tickets
WHERE resolution_time_raw IS NOT NULL
GROUP BY status;

-- 4.7 Uji silang dengan prioritas. Tiket urgent seharusnya paling cepat.
SELECT priority,
       COUNT(*) AS jumlah,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_time_raw)::NUMERIC, 0) AS median_raw
FROM tickets
WHERE resolution_time_raw IS NOT NULL
  AND status = 'resolved'
GROUP BY priority
ORDER BY median_raw;

-- 4.8 Tingkat tiket dibuka kembali
SELECT ROUND(SUM(reopened) * 100.0 / COUNT(*), 2) AS persen_reopened
FROM tickets;

--------------------------------------------------------------------------------
-- BAGIAN 5. CARA MEMUAT CSV DI POSTGRESQL
--------------------------------------------------------------------------------
-- Cara 1, lewat psql. Buka SQL Shell (psql), lalu jalankan:
--   \copy stg_tickets FROM 'C:/Users/Marco Alexander/Downloads/archive (12)/synthetic_it_support_tickets.csv' WITH (FORMAT csv, HEADER true, NULL '')
--
-- Perhatikan: gunakan garis miring biasa pada path, bukan garis miring terbalik.
-- Opsi NULL '' penting supaya teks NA pada kolom region tidak dianggap kosong.
--
-- Cara 2, lewat pgAdmin. Klik kanan tabel stg_tickets, pilih Import/Export Data,
-- pilih Import, arahkan ke berkas CSV, aktifkan Header, dan kosongkan kolom
-- NULL String.
--------------------------------------------------------------------------------
