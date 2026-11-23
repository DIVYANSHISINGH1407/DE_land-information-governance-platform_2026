-- =====================================================================
-- Phase 5 / CP4: Partitioning demonstration for the transactions table
--
-- This file demonstrates RANGE partitioning on `gpay.transactions` using
-- the `initiated_at` timestamptz column. It is intentionally isolated in
-- a separate schema (`gpay_demo`) and does NOT touch, drop, truncate, or
-- modify the existing `gpay.transactions` benchmark table.
--
-- To run against the large benchmark database:
--   psql -d gpay_cp4_large -f sql/08_partitioning.sql
-- =====================================================================

-- Use a dedicated demo schema so the existing benchmark tables are untouched.
DROP SCHEMA IF EXISTS gpay_demo CASCADE;
CREATE SCHEMA gpay_demo;
SET search_path TO gpay_demo;

-- ----------------------------------------------------------------------
-- 1. Partitioned parent table: transactions_demo
--
-- Column choice: initiated_at (timestamptz NOT NULL).
--   * It is the natural time dimension for UPI payments.
--   * Most queries filter or order by initiated_at (R01, R04, R05, R06,
--     R07, R08, R09, R14, R15, R19, R20, R23, R25).
--   * Data arrives roughly in time order, so RANGE partitioning aligns
--     with insert and query patterns.
--
-- Partitioning method: RANGE on initiated_at, one partition per month.
--   * Non-overlapping, contiguous month boundaries.
--   * Prunes to a single month for point/range lookups (see EXPLAIN below).
--
-- IMPORTANT: PostgreSQL requires that every PRIMARY KEY and UNIQUE
-- constraint on a partitioned table include ALL partition key columns.
-- Since we partition by `initiated_at`, the PK becomes (txn_id,
-- initiated_at) and the unique UPI reference becomes (upi_ref,
-- initiated_at). This is the primary-key rule for partitioned tables.
-- ----------------------------------------------------------------------

CREATE TABLE transactions_demo (
    txn_id       integer     NOT NULL,
    upi_ref      varchar(12) NOT NULL,
    txn_type     text        NOT NULL,
    payer_vpa    text        NOT NULL,
    payee_vpa    text        NOT NULL,
    merchant_id  integer,
    amount       numeric(12,2) NOT NULL,
    note         text,
    initiated_at timestamptz NOT NULL,
    completed_at timestamptz,
    status       text        NOT NULL,
    failure_code text,
    PRIMARY KEY (txn_id, initiated_at),
    UNIQUE (upi_ref, initiated_at)
) PARTITION BY RANGE (initiated_at);

-- ----------------------------------------------------------------------
-- 2. Example partitions: two non-overlapping months
--
-- June 2025 and June 2026 are chosen because they are real months present
-- in the large dataset and are far enough apart to clearly demonstrate
-- partition pruning (a query for one month never touches the other).
-- ----------------------------------------------------------------------

CREATE TABLE transactions_demo_y2025m06
    PARTITION OF transactions_demo
    FOR VALUES FROM ('2025-06-01 00:00:00+05:30')
    TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE transactions_demo_y2026m06
    PARTITION OF transactions_demo
    FOR VALUES FROM ('2026-06-01 00:00:00+05:30')
    TO ('2026-07-01 00:00:00+05:30');

-- ----------------------------------------------------------------------
-- 3. Seed each partition with a few representative rows so EXPLAIN can
--    show actual partition selection. Data mirrors the gpay schema.
-- ----------------------------------------------------------------------

INSERT INTO transactions_demo (txn_id, upi_ref, txn_type, payer_vpa, payee_vpa,
                               merchant_id, amount, note, initiated_at,
                               completed_at, status, failure_code)
VALUES
    (1,  '600000000001', 'P2P',  'alice@okhdfcbank',   'bob@oksbi',
     NULL, 250.00, 'Dinner', '2025-06-15 14:30:00+05:30',
     '2025-06-15 14:30:02+05:30', 'SUCCESS', NULL),
    (2,  '600000000002', 'P2M',  'carol@okicicibank',  'ganesh1@okbizaxis',
     1, 120.50, 'Groceries', '2025-06-20 09:15:00+05:30',
     '2025-06-20 09:15:04+05:30', 'SUCCESS', NULL),
    (3,  '600000000003', 'P2M',  'dave@okaxis',        'balaji2@okbizaxis',
     2, 80.00, 'Chai', '2026-06-10 18:45:00+05:30',
     '2026-06-10 18:45:03+05:30', 'FAILED', 'U16'),
    (4,  '600000000004', 'P2P',  'eve@oksbi',          'frank@okhdfcbank',
     NULL, 500.00, 'Rent', '2026-06-25 20:00:00+05:30',
     '2026-06-25 20:00:01+05:30', 'PENDING', NULL);

ANALYZE transactions_demo;

-- ----------------------------------------------------------------------
-- 4. EXPLAIN demonstrating partition pruning
--
-- Query A: single month (June 2026) -> should scan ONLY transactions_demo_y2026m06
-- Query B: two months       -> should scan both partitions
-- Query C: month with no data -> should scan zero partitions
-- ----------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS june_2026_payments
FROM transactions_demo
WHERE initiated_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND initiated_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30';

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS two_months
FROM transactions_demo
WHERE initiated_at >= TIMESTAMPTZ '2025-06-01 00:00:00+05:30'
  AND initiated_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30';

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS empty_month
FROM transactions_demo
WHERE initiated_at >= TIMESTAMPTZ '2027-01-01 00:00:00+05:30'
  AND initiated_at <  TIMESTAMPTZ '2027-02-01 00:00:00+05:30';

-- ----------------------------------------------------------------------
-- 5. Cleanup: remove the demo schema so the database is left unchanged.
--    (The DDL in this file remains as the permanent artifact.)
-- ----------------------------------------------------------------------

-- DROP SCHEMA gpay_demo CASCADE;

-- =====================================================================
-- Production considerations for partitioning `gpay.transactions`:
--
-- 1. PK / UNIQUE rule: any unique or primary constraint on a partitioned
--    table must contain the partition key (`initiated_at`). The existing
--    `transactions_pkey(txn_id)` and `transactions_upi_ref_key(upi_ref)`
--    would need to become (txn_id, initiated_at) and
--    (upi_ref, initiated_at). This changes index shape and FK references
--    from `disputes` and `rewards`, which reference `transactions(txn_id)`
--    alone — those FKs would need to be reworked to include `initiated_at`.
--
-- 2. Granularity: monthly partitions fit the 18-month data window. At
--    20× scale (~10M transactions/year), monthly partitions keep each
--    partition small enough for vacuuming and index maintenance in a
--    reasonable window.
--
-- 3. Partition maintenance: detach old partitions to an archive tablespace
--    or drop them after retention (e.g. 24 months). Use `ATTACH PARTITION`
--    to add future months before they are needed.
--
-- 4. Queries that do not filter on `initiated_at` (e.g. R17 grouping by
--    merchant_id across all time) cannot prune partitions and become
--    full-partition scans — they still benefit from the existing partial
--    indexes but not from pruning.
--
-- 5. Do not partition small dimension tables (cities, merchants) — the
--    overhead outweighs any benefit.
-- =====================================================================
