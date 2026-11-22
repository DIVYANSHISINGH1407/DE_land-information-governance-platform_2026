\set ON_ERROR_STOP on

CREATE TEMP TABLE stage_cities (
    city_id text, city_name text, state text
);
CREATE TEMP TABLE stage_users (
    user_id text, full_name text, phone text, email text, city_id text,
    kyc_status text, is_blocked text, created_at text
);
CREATE TEMP TABLE stage_bank_accounts (
    account_id text, user_id text, bank_name text, ifsc text, account_last4 text,
    account_type text, is_primary text, linked_at text
);
CREATE TEMP TABLE stage_vpas (
    vpa text, user_id text, account_id text, is_active text, created_at text
);
CREATE TEMP TABLE stage_merchants (
    merchant_id text, merchant_name text, mcc text, merchant_vpa text,
    city_id text, is_verified text, onboarded_on text
);
CREATE TEMP TABLE stage_transactions (
    txn_id text, upi_ref text, txn_type text, payer_vpa text, payee_vpa text,
    merchant_id text, amount text, note text, initiated_at text, completed_at text,
    status text, failure_code text
);
CREATE TEMP TABLE stage_rewards (
    reward_id text, user_id text, txn_id text, reward_type text, amount text,
    status text, issued_at text, expires_at text, credited_at text
);
CREATE TEMP TABLE stage_bill_payments (
    bill_id text, user_id text, biller_category text, biller_name text,
    consumer_number text, amount text, due_date text, status text, paid_at text
);
CREATE TEMP TABLE stage_disputes (
    dispute_id text, txn_id text, raised_by text, reason text,
    raised_at text, status text, resolved_at text
);

\copy stage_cities FROM 'large_data/cities.csv' WITH (FORMAT csv, HEADER true)
\copy stage_users FROM 'large_data/users.csv' WITH (FORMAT csv, HEADER true)
\copy stage_bank_accounts FROM 'large_data/bank_accounts.csv' WITH (FORMAT csv, HEADER true)
\copy stage_vpas FROM 'large_data/vpas.csv' WITH (FORMAT csv, HEADER true)
\copy stage_merchants FROM 'large_data/merchants.csv' WITH (FORMAT csv, HEADER true)
\copy stage_transactions FROM 'large_data/transactions.csv' WITH (FORMAT csv, HEADER true)
\copy stage_rewards FROM 'large_data/rewards.csv' WITH (FORMAT csv, HEADER true)
\copy stage_bill_payments FROM 'large_data/bill_payments.csv' WITH (FORMAT csv, HEADER true)
\copy stage_disputes FROM 'large_data/disputes.csv' WITH (FORMAT csv, HEADER true)

BEGIN;
SET LOCAL search_path TO gpay;

TRUNCATE TABLE
    disputes, rewards, bill_payments, transactions, vpas,
    bank_accounts, merchants, users, cities
CASCADE;

INSERT INTO cities
SELECT city_id::integer, city_name, state FROM stage_cities;

INSERT INTO users
SELECT user_id::integer, full_name, phone, NULLIF(email, ''), city_id::integer,
       kyc_status, is_blocked::boolean, created_at::timestamptz
FROM stage_users;

INSERT INTO bank_accounts
SELECT account_id::integer, user_id::integer, bank_name, ifsc, account_last4,
       account_type, is_primary::boolean, linked_at::timestamptz
FROM stage_bank_accounts;

INSERT INTO vpas
SELECT vpa, user_id::integer, account_id::integer, is_active::boolean,
       created_at::timestamptz
FROM stage_vpas;

INSERT INTO merchants
SELECT merchant_id::integer, merchant_name, mcc::smallint, merchant_vpa,
       city_id::integer, is_verified::boolean, onboarded_on::date
FROM stage_merchants;

INSERT INTO transactions
SELECT txn_id::integer, upi_ref, txn_type, payer_vpa, payee_vpa,
       NULLIF(merchant_id, '')::integer, amount::numeric(12, 2), NULLIF(note, ''),
       initiated_at::timestamptz, NULLIF(completed_at, '')::timestamptz,
       status, NULLIF(failure_code, '')
FROM stage_transactions;

INSERT INTO rewards
SELECT reward_id::integer, user_id::integer, txn_id::integer, reward_type,
       amount::numeric(8, 2), status, issued_at::timestamptz,
       expires_at::timestamptz, NULLIF(credited_at, '')::timestamptz
FROM stage_rewards;

INSERT INTO bill_payments
SELECT bill_id::integer, user_id::integer, biller_category, biller_name,
       consumer_number, amount::numeric(10, 2), due_date::date, status,
       NULLIF(paid_at, '')::timestamptz
FROM stage_bill_payments;

INSERT INTO disputes
SELECT dispute_id::integer, txn_id::integer, raised_by::integer, reason,
       raised_at::timestamptz, status, NULLIF(resolved_at, '')::timestamptz
FROM stage_disputes;

ANALYZE cities;
ANALYZE users;
ANALYZE bank_accounts;
ANALYZE vpas;
ANALYZE merchants;
ANALYZE transactions;
ANALYZE rewards;
ANALYZE bill_payments;
ANALYZE disputes;
COMMIT;
