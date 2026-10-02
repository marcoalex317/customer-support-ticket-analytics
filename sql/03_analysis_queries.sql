-- =============================================================================
-- Customer Support Ticket Analytics
-- 03 - Analysis queries
--
-- Database : PostgreSQL 17
-- Input    : fact_ticket and the dimension tables created by 02_build_star_schema.sql
-- Output   : one CSV per query, exported with \copy into outputs/
--
-- Run order: 01_load_and_verify.sql -> 02_build_star_schema.sql -> this file.
-- Every query below answers one business question stated in the findings report.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q1. How many tickets actually get resolved, and how long does each status take?
-- Output: outputs/by_status.csv
-- Note   : resolution_time_raw is only populated for resolved and
--          closed_no_action. The three unresolved statuses have no duration at
--          all, which is why they must never enter an average resolution time.
-- -----------------------------------------------------------------------------
SELECT
    f.status,
    COUNT(*)                                                      AS jumlah,
    COUNT(f.durasi_jam)                                           AS ada_durasi,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.durasi_jam)::numeric, 1)
                                                                  AS median_jam,
    COUNT(*) FILTER (WHERE f.durasi_jam > 106.9)                  AS di_atas_ambang
FROM fact_ticket f
GROUP BY f.status
ORDER BY jumlah DESC;


-- -----------------------------------------------------------------------------
-- Q2. Which attribute actually drives resolution time?
-- Output: outputs/dim_breakdown.csv
-- Note   : one UNION ALL block per dimension so every attribute is measured the
--          same way. persen_lama is the share of resolved tickets above the IQR
--          fence; it comes out 0.0 for every row, which is itself the finding.
-- -----------------------------------------------------------------------------
WITH dasar AS (
    SELECT f.priority, f.sla_plan, f.issue_type, f.product_area,
           f.channel, f.customer_segment, f.durasi_selesai_jam, f.flag_lama
    FROM fact_ticket f
    WHERE f.status = 'resolved'
),
ringkas AS (
    SELECT 'priority' AS dimensi, priority AS nilai, durasi_selesai_jam, flag_lama FROM dasar
    UNION ALL SELECT 'sla_plan',         sla_plan,         durasi_selesai_jam, flag_lama FROM dasar
    UNION ALL SELECT 'issue_type',       issue_type,       durasi_selesai_jam, flag_lama FROM dasar
    UNION ALL SELECT 'product_area',     product_area,     durasi_selesai_jam, flag_lama FROM dasar
    UNION ALL SELECT 'channel',          channel,          durasi_selesai_jam, flag_lama FROM dasar
    UNION ALL SELECT 'customer_segment', customer_segment, durasi_selesai_jam, flag_lama FROM dasar
)
SELECT
    dimensi,
    nilai,
    COUNT(*)                                                           AS jumlah,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY durasi_selesai_jam)::numeric, 1)
                                                                       AS median_jam,
    ROUND(100.0 * AVG(flag_lama), 1)                                   AS persen_lama
FROM ringkas
GROUP BY dimensi, nilai
ORDER BY dimensi, median_jam DESC;


-- -----------------------------------------------------------------------------
-- Q3. Is priority assigned according to the type of problem?
-- Output: outputs/priority_vs_issue.csv
-- -----------------------------------------------------------------------------
SELECT
    f.issue_type,
    f.priority,
    COUNT(*)                                                        AS jumlah,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY f.issue_type), 1)
                                                                    AS persen_dalam_issue
FROM fact_ticket f
GROUP BY f.issue_type, f.priority
ORDER BY f.issue_type, f.priority;


-- -----------------------------------------------------------------------------
-- Q4. Do customers on a higher SLA plan get higher priority?
-- Output: outputs/sla_vs_priority.csv
-- -----------------------------------------------------------------------------
SELECT
    f.sla_plan,
    f.priority,
    COUNT(*)                                                        AS jumlah,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY f.sla_plan), 1)
                                                                    AS persen_dalam_sla
FROM fact_ticket f
GROUP BY f.sla_plan, f.priority
ORDER BY f.sla_plan, f.priority;


-- -----------------------------------------------------------------------------
-- Q5a. Monthly intake, abandonment and speed.
-- Output: outputs/trend_bulanan.csv
-- -----------------------------------------------------------------------------
SELECT
    DATE_TRUNC('month', f.tanggal_dibuat)::date                     AS bulan,
    COUNT(*)                                                        AS tiket,
    COUNT(*) FILTER (WHERE f.status = 'closed_no_action')           AS terbengkalai,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.durasi_selesai_jam)::numeric, 1)
                                                                    AS median_jam
FROM fact_ticket f
GROUP BY 1
ORDER BY 1;


-- -----------------------------------------------------------------------------
-- Q5b. Cumulative backlog: tickets created minus tickets closed, month by month.
-- Output: outputs/backlog_kumulatif.csv
-- Note   : a ticket counts as closed in the month of tanggal_tutup, which is
--          created_at plus resolution_time_hours. This is the SQL equivalent of
--          the Backlog Kumulatif DAX measure, and the two must agree.
-- -----------------------------------------------------------------------------
WITH bulan AS (
    SELECT DISTINCT DATE_TRUNC('month', d.tanggal)::date AS bulan
    FROM dim_date d
    WHERE d.tanggal BETWEEN DATE '2022-01-01' AND DATE '2025-12-31'
),
dibuat AS (
    SELECT DATE_TRUNC('month', tanggal_dibuat)::date AS bulan, COUNT(*) AS n
    FROM fact_ticket GROUP BY 1
),
ditutup AS (
    SELECT DATE_TRUNC('month', tanggal_tutup)::date AS bulan, COUNT(*) AS n
    FROM fact_ticket WHERE tanggal_tutup IS NOT NULL GROUP BY 1
)
SELECT
    b.bulan,
    COALESCE(dib.n, 0)                                              AS dibuat,
    COALESCE(dit.n, 0)                                              AS ditutup,
    SUM(COALESCE(dib.n, 0) - COALESCE(dit.n, 0)) OVER (ORDER BY b.bulan)
                                                                    AS backlog_kumulatif
FROM bulan b
LEFT JOIN dibuat  dib ON dib.bulan = b.bulan
LEFT JOIN ditutup dit ON dit.bulan = b.bulan
ORDER BY b.bulan;


-- -----------------------------------------------------------------------------
-- Q6a. How old is the unresolved backlog, per status?
-- Output: outputs/umur_model.csv
-- Note   : kelompok_umur is computed in 02_build_star_schema.sql as a whole-day
--          difference between 2025-12-30 and the ticket creation date. Using
--          timestamp arithmetic instead shifts boundary tickets between buckets,
--          so always read the age from this column.
-- -----------------------------------------------------------------------------
SELECT
    kelompok_umur,
    COUNT(*) FILTER (WHERE status = 'in_progress')                  AS in_progress,
    COUNT(*) FILTER (WHERE status = 'on_hold')                      AS on_hold,
    COUNT(*) FILTER (WHERE status = 'open')                         AS open,
    COUNT(*)                                                        AS total
FROM fact_ticket
WHERE kelompok_umur IS NOT NULL
GROUP BY kelompok_umur
ORDER BY kelompok_umur;


-- -----------------------------------------------------------------------------
-- Q6b. Duration distribution, resolved against closed without action.
-- Output: outputs/distribusi_durasi.csv
-- Note   : this is the query behind the clearest chart in the report. Resolved
--          tickets stop at 72 hours; every bucket beyond that is abandonment.
-- -----------------------------------------------------------------------------
SELECT
    (FLOOR(durasi_jam / 10) * 10)::int                              AS mulai_jam,
    COUNT(*) FILTER (WHERE status = 'resolved')                     AS selesai,
    COUNT(*) FILTER (WHERE status = 'closed_no_action')             AS terbengkalai
FROM fact_ticket
WHERE durasi_jam IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- -----------------------------------------------------------------------------
-- Q7a. Does service quality differ by priority?
-- Output: outputs/kualitas.csv
-- Note   : csat_score is 0 on roughly 30 percent of rows and that 0 is spread
--          evenly across every status, so it is treated as "not rated" and
--          excluded through csat_dinilai rather than averaged as a real zero.
-- -----------------------------------------------------------------------------
SELECT
    f.priority,
    ROUND(AVG(f.csat_dinilai)::numeric, 2)                          AS csat,
    COUNT(*) FILTER (WHERE f.csat_dinilai IS NULL)                  AS tanpa_nilai,
    ROUND(100.0 * AVG(f.reopened), 2)                               AS persen_reopened
FROM fact_ticket f
GROUP BY f.priority
ORDER BY f.priority;


-- -----------------------------------------------------------------------------
-- Q7b. Do customers punish slow tickets with lower satisfaction?
-- Output: outputs/durasi_vs_kepuasan.csv
-- -----------------------------------------------------------------------------
SELECT
    f.kelompok_durasi                                               AS kelompok,
    COUNT(*)                                                        AS jumlah,
    ROUND(AVG(f.csat_dinilai)::numeric, 2)                          AS csat,
    ROUND(100.0 * AVG(f.reopened), 2)                               AS persen_reopened
FROM fact_ticket f
WHERE f.kelompok_durasi IS NOT NULL
GROUP BY f.kelompok_durasi
ORDER BY f.kelompok_durasi;


-- -----------------------------------------------------------------------------
-- Q8. Control check: is ticket volume evenly spread across region and platform?
-- Output: outputs/region_platform.csv
-- Note   : a flat result here is what first suggested the dataset is synthetic.
-- -----------------------------------------------------------------------------
SELECT f.region, f.platform, COUNT(*) AS jumlah
FROM fact_ticket f
GROUP BY f.region, f.platform
ORDER BY f.region, f.platform;


-- -----------------------------------------------------------------------------
-- Model verification. Run this after every rebuild; the dashboard must match.
-- Output: outputs/verifikasi_model.csv
-- -----------------------------------------------------------------------------
SELECT 'baris_dim_date'              AS metrik, COUNT(*)::text AS nilai FROM dim_date
UNION ALL
SELECT 'baris_fakta',                            COUNT(*)::text FROM fact_ticket
UNION ALL
SELECT 'umur: ' || kelompok_umur,                COUNT(*)::text
FROM fact_ticket WHERE kelompok_umur IS NOT NULL GROUP BY kelompok_umur
UNION ALL
SELECT 'tanggal_tutup_terisi',                   COUNT(*)::text
FROM fact_ticket WHERE tanggal_tutup IS NOT NULL
UNION ALL
SELECT 'tiket_selesai_di_atas_ambang',           SUM(flag_lama)::text FROM fact_ticket;


-- =============================================================================
-- Exporting the results
-- Run each query above inside a \copy to write the CSV, for example:
--
--   \copy (SELECT ... ) TO 'outputs/by_status.csv' CSV HEADER
--
-- \copy writes on the client side, so the path is relative to wherever psql was
-- started. Plain COPY writes on the server and will fail without superuser.
-- =============================================================================
