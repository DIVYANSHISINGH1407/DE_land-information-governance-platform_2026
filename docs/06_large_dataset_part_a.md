# CP4 Part A: Large Dataset Scaling and Integrity

## Scope

This deliverable covers only dataset scaling, generation, loading, and integrity
verification. It does not contain benchmark execution or benchmark analysis.

The faculty-provided `large_data.zip` was not present at inspection time, so a
deterministic 20× fallback is provided. It preserves every seed row and creates
fresh synthetic rows for the fact and account data. `seed_data/*.csv` is never
read for writing and is not modified.

## Scale targets

| Table | Seed rows | 20× target |
|---|---:|---:|
| cities | 10 | 10 (dimension unchanged) |
| users | 40,000 | 800,000 |
| bank_accounts | 53,333 | 1,066,660 |
| vpas | 53,333 | 1,066,660 |
| merchants | 3,000 | 60,000 |
| transactions | 250,468 | 5,009,360 |
| rewards | 39,799 | 795,980 |
| bill_payments | 30,000 | 600,000 |
| disputes | 3,569 | 71,380 |

## Files

- `scripts/generate_large_data.py`: deterministic CSV generator.
- `sql/07_load_large_data.sql`: staged, transactional, repeatable loader.
- `sql/08_verify_large_data.sql`: row counts and relationship/uniqueness checks.
- `large_data/manifest.csv`: generated row counts and byte sizes.
- `large_data/*.csv`: generated scaled dataset; excluded by `.gitignore`.

## Generate

From the repository root:

```bash
python3 scripts/generate_large_data.py
```

To replace an existing generated dataset:

```bash
python3 scripts/generate_large_data.py --force
```

The generator creates a staging directory, writes all generated files there, and
atomically replaces the individual CSV files. It does not touch `seed_data.zip`
or `seed_data/*.csv`.

## Create and load

Create a separate database, run the existing CP1 schema script, then load the
generated dataset:

```bash
createdb gpay_cp4_large
psql -d gpay_cp4_large -v ON_ERROR_STOP=1 -f sql/01_schema.sql
psql -d gpay_cp4_large -v ON_ERROR_STOP=1 -f sql/07_load_large_data.sql
psql -d gpay_cp4_large -v ON_ERROR_STOP=1 -f sql/08_verify_large_data.sql
```

The loader stages all input files before one transaction, truncates existing
large-dataset tables in child-to-parent order, inserts all scaled rows, and
runs `ANALYZE`. Re-running it replaces the loaded scaled data rather than
appending duplicates.

## Integrity guarantees

- Synthetic IDs are assigned outside seed ID ranges or selected without collision.
- Synthetic phone numbers, VPAs, merchant VPAs, and UPI references are unique.
- Synthetic bank accounts are paired only with existing or synthetic users.
- Synthetic VPAs are paired only with accounts belonging to the same user.
- P2M transactions use a matching merchant ID and merchant VPA.
- P2P transactions have no merchant ID.
- Rewards reference existing users and transactions.
- Bills reference existing users.
- Disputes reference existing transactions and users.
- Status-dependent completion, failure, and resolution fields follow the existing
  `gpay` schema constraints.

Run `sql/08_verify_large_data.sql` after loading. It reports row counts, raises
an exception for any missing FK relationship, and lists duplicate-count checks.

## Actual verification results

The following was executed on PostgreSQL in the local test database
`gpay_cp4_part_a_verification`.

### Dataset sizes

| Item | Actual size |
|---|---:|
| Original `seed_data.zip` | 12 MB |
| Uncompressed `seed_data/` | 53 MB |
| Generated `large_data/` | 1.1 GB |
| Verification database | 1861 MB |

Generated CSV line counts include the header:

| CSV | Data rows |
|---|---:|
| cities.csv | 10 |
| users.csv | 800,000 |
| bank_accounts.csv | 1,066,660 |
| vpas.csv | 1,066,660 |
| merchants.csv | 60,000 |
| transactions.csv | 5,009,360 |
| rewards.csv | 795,980 |
| bill_payments.csv | 600,000 |
| disputes.csv | 71,380 |

### PostgreSQL load

- Database and CP1 schema creation: passed.
- First successful load: passed.
- Repeat load after `TRUNCATE`: passed.
- Final repeat verification: passed.
- Row counts matched every manifest target exactly.
- Duplicate primary/natural-key counts were `0` for all 12 checked keys.
- Foreign-key and relationship checks raised no violations.

| Table | PostgreSQL total relation size |
|---|---:|
| transactions | 1180 MB |
| users | 215 MB |
| vpas | 151 MB |
| bank_accounts | 130 MB |
| rewards | 89 MB |
| bill_payments | 66 MB |
| merchants | 14 MB |
| disputes | 7768 kB |
| cities | 32 kB |

The first actual load attempt identified and led to a fix for synthetic UPI
reference collisions. A later collision-safe regeneration and load passed.

## Pending work

- Replace the reproducible fallback with faculty `large_data.zip` if/when that
  exact release is available. If the exact CSV data differs, regenerate or load
  that release instead of modifying the original seed or CP1-CP3 files.
- Run benchmark analysis, partitioning implementation, and the CP4 large
  performance report only after the exact CP4 benchmark dataset and CP3
  optimization files are available. Those items belong to the benchmark/scale
  analysis scope and are not implemented in this Part A deliverable.
