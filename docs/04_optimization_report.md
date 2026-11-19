# CP3 — Query Optimization Report

## Benchmark method

The baseline timings are from the three-run CP2 benchmark in `benchmarks/results/baseline/summary.csv`. The optimized timings were measured with five runs, as required for CP3, using `benchmarks/run_benchmark.sh gpay_cp3_benchmark optimized 5 sql/06_optimized_queries.sql`. Both runs used the same local machine, PostgreSQL 18.4, the 250,468-row seed dataset, and the `Asia/Kolkata` time zone. Write statements ran inside `BEGIN`/`ROLLBACK`. The optimized raw plans are in `benchmarks/results/optimized/`; the generated summary is `benchmarks/results/optimized/summary.csv`.

Baseline averages use three runs and optimized averages use five, so small differences should be treated as approximate. Timing averages are copied from the benchmark summaries; sample plan times and index sizes come from the raw plans and database size queries.

## Results

Improvement is `(before − after) / before × 100`. A positive value means faster. “Same result?” refers to the original workload result, except R13, where the original query had the NULL bug described below.

| Query | Before (ms) | Plan issue and change | After (ms) | Improvement | Same result? |
|---|---:|---|---:|---:|:---:|
| R01 | 21.401 | Split the payer/payee OR into two indexed branches with UNION to remove duplicate payments. | 0.155 | 99.3% | ✅ |
| R02 | 0.042 | No rewrite; the VPA and user primary-key indexes already make this lookup fast. | 0.092 | -119.0% | ✅ |
| R03 | 12.074 | Use a half-open timestamp range and user-to-VPA plus payer/time indexes. | 0.038 | 99.7% | ✅ |
| R04 | 7.546 | Use partial indexes for pending rows and the pending callback lookup. | 0.052 | 99.3% | ✅ |
| R05 | 7.048 | Use a merchant/time index that also covers the amount and status. | 0.043 | 99.4% | ✅ |
| R06 | 7.065 | Use the success-only time index for the settlement date range. | 0.421 | 94.0% | ✅ |
| R07 | 7.649 | Use a partial index for failed transactions in the recent-time range. | 1.845 | 75.9% | ✅ |
| R08 | 130.188 | Use a partial P2P success index ordered by payee and time for grouping. | 48.822 | 62.5% | ✅ |
| R09 | 272.989 | Keep the window query; payer/time index reduces table reads, but it still processes all successful rows. | 123.028 | 54.9% | ✅ |
| R10 | 1.499 | Use a user/expiry index limited to unscratched rewards. | 0.043 | 97.1% | ✅ |
| R11 | 1.579 | Use an expiry-ordered partial index for unscratched rewards. | 0.054 | 96.6% | ✅ |
| R12 | 1.162 | Use a user/due-date index limited to bills still due. | 0.043 | 96.3% | ✅ |
| R13 | 23.661 | Replace NULL-sensitive NOT IN with NOT EXISTS; this fixes the empty result. | 1.193 | 95.0% | ⚠️ intended result corrected |
| R14 | 17.556 | Use a half-open timestamp range and start from the user’s VPA index. | 0.106 | 99.4% | ✅ |
| R15 | 8.523 | Use the success-only time index to find the month’s merchant transactions. | 2.977 | 65.1% | ✅ |
| R16 | 0.294 | Use an index containing only open disputes, ordered by raised time. | 0.156 | 46.9% | ✅ |
| R17 | 11.959 | Use a partial merchant/status index for P2M transactions. | 8.455 | 29.3% | ✅ |
| R18 | 24.195 | No rewrite; the payer index helps joins, but aggregation still needs many successful payments. | 17.290 | 28.5% | ✅ |
| R19 | 4851.212 | Aggregate transaction activity once, then left join it to verified Bengaluru merchants. | 11.786 | 99.8% | ✅ |
| R20 | 10.591 | Replace the date cast in the filter with a half-open timestamp range; use the page/time index. | 2.181 | 79.4% | ✅ |
| R21 | 1.140 | Add pg_trgm and a GIN trigram index for the leading-wildcard ILIKE search. | 0.247 | 78.3% | ✅ |
| R22 | 3.369 | No rewrite; the account lookup is indexed, while scanning the small VPA table is still cheaper. | 3.037 | 9.9% | ✅ |
| R23 | 63.102 | Add an index in newest-first order so PostgreSQL can skip to the requested page without sorting all rows. | 12.081 | 80.9% | ✅ |
| R24 | 0.030 | No rewrite; the unique UPI-reference index already handles the lookup. | 0.018 | 40.0% | ✅ |
| R25 | 22.396 | Use a covering time index for completed transactions and their payer VPA. | 13.543 | 39.5% | ✅ |
| W01 | 0.610 | No rewrite; the new transaction indexes add maintenance work to inserts. | 1.036 | -69.8% | ✅ |
| W02 | 20.384 | Use a partial pending-ID index to find the oldest pending transaction quickly. | 0.267 | 98.7% | ✅ |
| W03 | 1.627 | Use a partial user/ID index to find the oldest unscratched reward. | 0.210 | 87.1% | ✅ |
| W04 | 2.144 | Use an expiry-ordered partial index for the reward-expiry job. | 0.256 | 88.1% | ✅ |
| W05 | 2.201 | Use a partial due-date index for bills that are still due. | 1.065 | 51.6% | ✅ |
| **Total of the 30 averages** | **5535.236** | Sum of per-query averages; included as a workload-level reference. | **250.540** | **95.5%** | — |

R02 had a noisy five-run average (0.092 ms, median 0.045 ms, maximum 0.285 ms). Its query and plan are unchanged, and the median is close to baseline.

### What changed in the results

- R19 was the largest original bottleneck: it repeatedly scanned all transactions for each qualifying merchant. The rewrite calculates the merchant totals once and cuts the measured average from 4,851.212 ms to 11.786 ms.
- R03 and R14 no longer apply a function to `initiated_at` in the filter. This lets PostgreSQL use the timestamp indexes. R14’s source query says “2026” in its description but its actual predicate is `EXTRACT(YEAR ...) >= 2025`; the rewrite preserves the SQL predicate’s meaning.
- R01’s UNION removes duplicate transaction rows if a user has a VPA on both sides of a payment, matching the original OR condition while allowing payer and payee index scans.
- R23 still uses the supplied fixed `OFFSET 200000` page. Its ordered index reduced sorting and deep-page time, but it must still walk past 200,000 entries.
- R08 and R09 still aggregate or process a large share of successful transactions, so their improvement is smaller than the point lookups. R17 also remains an aggregate over P2M payments.
- R18 and R22 were not rewritten. R18 benefits from the transaction index but still aggregates many rows; R22 is already small. R23 keeps the exact page from the supplied workload.

## Result checks for rewritten queries

For R01, R03, R14, R19 and R20, I compared the original and optimized result sets in both directions with `EXCEPT ALL`. Each comparison returned **0 changed rows**. R03, R14 and R20 were checked with the session time zone set to `Asia/Kolkata`, which is also the benchmark time zone. R13 is intentionally different because its original result is incorrect.

R13’s subquery contains `NULL` merchant IDs from P2P transactions. In SQL, `NOT IN` with a NULL in the list does not evaluate true for any merchant, so the original query returned **0** rows. The `NOT EXISTS` version returned **450** merchants with no matching transaction. This matches the business request and fixes the NULL-related wrong answer called out in the project brief.

```sql
-- Correct anti-join for R13
SELECT m.merchant_id, m.merchant_name, m.onboarded_on
FROM merchants m
WHERE NOT EXISTS (
    SELECT 1
    FROM transactions t
    WHERE t.merchant_id = m.merchant_id
);
```

The remaining 24 statements were copied unchanged from `queries/workload_30.sql`; their output is therefore unchanged by the query text. Indexes only change access paths.

## Before/after plan evidence

The plans below summarize the third baseline run and fifth optimized run. R07 also had one timing outlier (0.710–6.334 ms; median 0.723 ms), so its average is less representative than the other runs. Full `EXPLAIN (ANALYZE, BUFFERS)` output for all runs is saved in the raw plan files linked by their filenames.

### R19 — merchant report

- **Before:** Baseline: sequential scan of the 3,000 merchants; for each of the 239 matches, both correlated subqueries sequentially scanned `transactions` (478 full transaction scans total). Average: **4,851.212 ms**.
- **After:** Optimized: one `Index Only Scan` on `idx_transactions_merchant_time`, one `GroupAggregate`, then a `Merge Left Join` to the merchants. Fifth-run plan: **10.507 ms**; five-run average: **11.786 ms**.
- **Raw plans:** [baseline R19](../benchmarks/results/baseline/R19.txt) · [optimized R19](../benchmarks/results/optimized/R19.txt)

### R03 — daily limit check

- **Before:** Baseline: parallel sequential scan of `transactions` and sequential scan of `vpas`; `DATE(initiated_at)` prevented a plain timestamp range lookup. Average: **12.074 ms**.
- **After:** Optimized: index-only lookup of the user’s VPAs and a parameterized index-only range scan on `idx_transactions_payer_time_active`. Fifth-run plan: **0.033 ms**; five-run average: **0.038 ms**.
- **Raw plans:** [baseline R03](../benchmarks/results/baseline/R03.txt) · [optimized R03](../benchmarks/results/optimized/R03.txt)

### R14 — spending by MCC

- **Before:** Baseline: sequential scans of `transactions` and `vpas`, followed by joins and aggregation. Average: **17.556 ms**.
- **After:** Optimized: user VPA index lookup, bitmap index/heap access to the matching successful payments, and merchant primary-key lookups. Fifth-run plan: **0.092 ms**; five-run average: **0.106 ms**.
- **Raw plans:** [baseline R14](../benchmarks/results/baseline/R14.txt) · [optimized R14](../benchmarks/results/optimized/R14.txt)

### R05 — merchant hourly collections

- **Before:** Baseline: parallel sequential scan of the full transaction table for one merchant and one day. Average: **7.048 ms**.
- **After:** Optimized: index-only range scan on `idx_transactions_merchant_time`, followed by a small grouping step. Fifth-run plan: **0.041 ms**; five-run average: **0.043 ms**.
- **Raw plans:** [baseline R05](../benchmarks/results/baseline/R05.txt) · [optimized R05](../benchmarks/results/optimized/R05.txt)

### R04 — stale pending payments

- **Before:** Baseline: parallel sequential scan of all transactions and a sort. Average: **7.546 ms**.
- **After:** Optimized: scan of the small partial pending-payment index, then sort the qualifying rows. Fifth-run plan: **0.049 ms**; five-run average: **0.052 ms**.
- **Raw plans:** [baseline R04](../benchmarks/results/baseline/R04.txt) · [optimized R04](../benchmarks/results/optimized/R04.txt)

## Write overhead

| Write query | Baseline average (ms) | Optimized average (ms) | Change |
|---|---:|---:|---:|
| W01 | 0.610 | 1.036 | +69.8% (+0.426 ms) |
| W02 | 20.384 | 0.267 | -98.7% (-20.117 ms) |
| W03 | 1.627 | 0.210 | -87.1% (-1.417 ms) |
| W04 | 2.144 | 0.256 | -88.1% (-1.888 ms) |
| W05 | 2.201 | 1.065 | -51.6% (-1.136 ms) |

W01 insert time increased because each new transaction must also be added to the workload indexes. At about 1.036 ms on this seed database, it remains small in absolute terms, but the percentage increase is real. W02–W05 were faster because their target-row searches use the new partial indexes.

## Index storage

Index sizes below come from `pg_relation_size(indexrelid)` after loading and analyzing the seed database. Table sizes use `pg_table_size`. The 22 added indexes use **155 MB** in total; the transaction table is **35 MB**, and its 14 added indexes use **151 MB**. This is a substantial storage and write-cost trade-off that should be reviewed again on the large dataset.

| Table | Table size | Added index | Index size | Index / table |
|---|---:|---|---:|---:|
| bill_payments | 3,088 kB | idx_bills_due_date | 32 kB | 1.0% |
| bill_payments | 3,088 kB | idx_bills_due_user_date | 96 kB | 3.1% |
| disputes | 376 kB | idx_disputes_open_raised_at | 16 kB | 4.3% |
| merchants | 312 kB | idx_merchants_name_trgm | 224 kB | 71.8% |
| rewards | 3,648 kB | idx_rewards_unscratched_expiry | 32 kB | 0.9% |
| rewards | 3,648 kB | idx_rewards_unscratched_user_expiry | 48 kB | 1.3% |
| rewards | 3,648 kB | idx_rewards_unscratched_user_id | 32 kB | 0.9% |
| transactions | 35 MB | idx_transactions_completed_time | 15 MB | 43.0% |
| transactions | 35 MB | idx_transactions_failed_time | 728 kB | 2.0% |
| transactions | 35 MB | idx_transactions_merchant_id_present | 992 kB | 2.8% |
| transactions | 35 MB | idx_transactions_merchant_time | 6,800 kB | 19.1% |
| transactions | 35 MB | idx_transactions_p2m_merchant_status | 4,328 kB | 12.2% |
| transactions | 35 MB | idx_transactions_page_time | 16 MB | 46.5% |
| transactions | 35 MB | idx_transactions_payee_time | 28 MB | 81.1% |
| transactions | 35 MB | idx_transactions_payer_time | 28 MB | 81.1% |
| transactions | 35 MB | idx_transactions_payer_time_active | 14 MB | 40.3% |
| transactions | 35 MB | idx_transactions_pending_time | 32 kB | 0.1% |
| transactions | 35 MB | idx_transactions_pending_txn_id | 16 kB | 0.0% |
| transactions | 35 MB | idx_transactions_success_p2p_day | 9,040 kB | 25.5% |
| transactions | 35 MB | idx_transactions_success_pair_time | 20 MB | 56.5% |
| transactions | 35 MB | idx_transactions_success_time | 9,240 kB | 26.0% |
| vpas | 4,064 kB | idx_vpas_user_id_cover | 3,112 kB | 76.6% |

`idx_merchants_name_trgm` is relatively large compared with the small merchants table, but it makes the leading-wildcard search fast. The large covering transaction indexes avoid heap reads for frequently used queries; they also account for most of the extra storage.

## Queries that did not benefit much

- R09 still has to process more than 230,000 successful transactions for its window function; the index reduces heap access and helps ordering, but the scan and window work remain.
- R17 still groups a large set of P2M payments, so its improvement is modest.
- R18 needs totals across many users and transactions. It is faster in the final run, but the scan and aggregation dominate.
- R23 is much faster with the ordered index, but deep OFFSET pagination still walks through the 200,000 preceding entries. A real application should use keyset pagination with a cursor; that would change the fixed page input in this benchmark.
- R20 still groups all transactions in the selected month. The index reduces the rows visited, but a scan of that month is still needed.

## Reproducing the optimized benchmark

```bash
PGTZ=Asia/Kolkata ./benchmarks/run_benchmark.sh gpay_cp3_benchmark optimized 5 sql/06_optimized_queries.sql
```

`sql/05_indexes.sql` includes `CREATE EXTENSION IF NOT EXISTS pg_trgm` for R21. The PostgreSQL role running the index script needs permission to install that extension.
