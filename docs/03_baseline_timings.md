# CP2 — Baseline Query Timings

## Method

The 30 statements in `queries/workload_30.sql` were run unchanged against PostgreSQL 18.4 in the dedicated local database `gpay_cp1_cp2_benchmark`, with `search_path` set to `gpay` and the session time zone set to `Asia/Kolkata`. Each statement used `EXPLAIN (ANALYZE, BUFFERS)` for three runs. Write statements were run inside a transaction and rolled back after each run. The transaction count remained 250,468 and the number of pending rows remained 125 after all write-query tests.

The execution times below are copied from the raw plan `Execution Time` values. Averages are arithmetic means rounded to three decimal places by the benchmark script. `scan nodes` describes the scan nodes observed in the third run. The database has only primary/unique-constraint indexes; no CP3 indexes or query rewrites were applied.

Raw plans for all three runs are in `benchmarks/results/baseline/R01.txt` through `W05.txt`. The generated machine-readable summary is `benchmarks/results/baseline/summary.csv`.

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Observed scan nodes / explanation |
|---|---|---|---:|---:|---:|---:|---|
| R01 | READ | User 15177 transaction history | 28.266 | 20.019 | 15.917 | 21.401 | Sequential scans of transactions and VPAs; both participant filters lack supporting indexes. |
| R02 | READ | Check whether a VPA exists and show its user | 0.056 | 0.037 | 0.032 | 0.042 | Index scans use VPA and user primary keys for equality joins/lookups. |
| R03 | READ | Sum user 15177's sent amount for June 30 | 12.418 | 12.049 | 11.754 | 12.074 | Sequential scans of transactions and VPAs; date and user predicates have no tuning indexes. |
| R04 | READ | Find stale pending payments | 7.718 | 7.556 | 7.363 | 7.546 | Sequential transaction scan for status and initiation-time predicates. |
| R05 | READ | Hourly collections for merchant 2 | 7.517 | 6.823 | 6.804 | 7.048 | Sequential transaction scan for merchant, status, and time range. |
| R06 | READ | Calculate merchant settlement totals | 7.626 | 7.009 | 6.559 | 7.065 | Sequential transaction scan; merchant primary-key lookup supports the join. |
| R07 | READ | Count failure codes by payer bank | 7.638 | 7.289 | 8.019 | 7.649 | Sequential transaction scan; VPA and account lookups use key indexes. |
| R08 | READ | Find P2P VPAs receiving from 5+ payers per day | 128.972 | 131.690 | 129.902 | 130.188 | Sequential scan of all transactions, followed by grouping and distinct aggregation. |
| R09 | READ | Find repeated successful payments within 10 minutes | 273.802 | 273.555 | 271.611 | 272.989 | Sequential scan of transactions for the window-function input. |
| R10 | READ | User 15177's unexpired unscratched rewards | 1.648 | 1.497 | 1.352 | 1.499 | Sequential scan of rewards for user, status, and expiry. |
| R11 | READ | Unscratched rewards expiring before July 4 | 1.634 | 1.548 | 1.554 | 1.579 | Sequential scan of rewards for status and expiry. |
| R12 | READ | User 1072's bills due July 1–7 | 1.100 | 1.085 | 1.302 | 1.162 | Sequential scan of bills for user, status, and due date. |
| R13 | READ | Merchants absent from the transaction subquery | 23.733 | 23.709 | 23.542 | 23.661 | Sequential scans of merchants and transactions for the anti-membership test. |
| R14 | READ | Spending by MCC for user 15177 | 17.591 | 17.573 | 17.503 | 17.556 | Sequential scans of transactions and VPAs; merchant key lookups support the join. |
| R15 | READ | Top 10 merchant GMV per city in June | 8.213 | 8.552 | 8.804 | 8.523 | Sequential scans of transactions and merchants before grouping/ranking. |
| R16 | READ | Disputes open before June 23 | 0.297 | 0.293 | 0.293 | 0.294 | Sequential scan of the small disputes table; transaction PK lookup supports the join. |
| R17 | READ | Refund percentage by merchant | 11.877 | 12.066 | 11.934 | 11.959 | Sequential transaction scan and grouped filtered counts. |
| R18 | READ | Non-verified users with at least ₹10,000 sent | 24.392 | 24.184 | 24.009 | 24.195 | Sequential scans of transactions, VPAs, and users for joins and aggregation. |
| R19 | READ | Payment summary for verified Bengaluru merchants | 4793.040 | 4838.502 | 4922.094 | 4851.212 | Sequential scans of merchants and transactions; correlated subqueries repeatedly inspect transactions. |
| R20 | READ | Daily success rates in June | 10.970 | 10.320 | 10.482 | 10.591 | Sequential transaction scan; date cast and grouping require examining the time range. |
| R21 | READ | Merchant names containing “chai” | 1.261 | 1.075 | 1.083 | 1.140 | Sequential merchant scan; leading-wildcard `ILIKE` has no ordinary key lookup. |
| R22 | READ | User 15177's bank accounts and VPAs | 3.334 | 3.398 | 3.376 | 3.369 | Sequential VPA scan; account lookups use the account/user unique key. |
| R23 | READ | Transactions at offset 200,000 | 62.980 | 63.181 | 63.144 | 63.102 | Sequential transaction scan to produce the ordered deep-offset page. |
| R24 | READ | Look up a payment by UPI reference | 0.033 | 0.027 | 0.031 | 0.030 | Unique index scan on `transactions.upi_ref`. |
| R25 | READ | Average completion time by payer bank | 22.267 | 22.782 | 22.139 | 22.396 | Sequential scans of transactions, VPAs, and bank accounts for the time filter and joins. |
| W01 | WRITE | Insert a pending P2M payment | 0.589 | 0.589 | 0.653 | 0.610 | Insert plan; no table scan. The transaction was rolled back. |
| W02 | WRITE | Complete the oldest pending payment | 20.384 | 20.328 | 20.440 | 20.384 | Primary-key index scan for the selected transaction; update was rolled back. |
| W03 | WRITE | Credit the oldest unscratched reward for user 15177 | 1.614 | 1.666 | 1.601 | 1.627 | Sequential reward scan for the subquery, then reward primary-key scan; rolled back. |
| W04 | WRITE | Expire rewards before July 4 | 2.539 | 1.903 | 1.990 | 2.144 | Sequential reward scan for status and expiry; update was rolled back. |
| W05 | WRITE | Mark past-due bills overdue | 2.171 | 2.381 | 2.052 | 2.201 | Sequential bill scan for status and due date; update was rolled back. |

## Notes on interpreting the baseline

* R19 is the slowest query in this baseline at about 4.85 seconds. Its two correlated transaction subqueries are executed for each qualifying merchant, so the plan repeatedly inspects the transaction table.
* R08 and R09 perform grouping/window processing over the transaction population and are the next most expensive read queries in this run.
* R13 and R14 are benchmarked exactly as supplied. In the source data, `transactions.merchant_id` is `NULL` for P2P rows, so R13's `NOT IN` subquery includes `NULL`; SQL three-valued logic can therefore make the anti-membership predicate return no merchants. R14's predicate is `EXTRACT(YEAR ...) >= 2025`, despite its description referring to 2026. Neither query was changed for CP2.
* Timings are machine- and load-dependent. The raw plans are the source of truth; these baseline values should only be compared with later phases measured on the same environment.
