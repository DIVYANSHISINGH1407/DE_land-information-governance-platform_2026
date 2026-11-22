\set ON_ERROR_STOP on
\set search_path TO gpay

SET search_path TO gpay;

\echo 'Row counts'
SELECT 'cities' AS table_name, count(*) AS row_count FROM cities
UNION ALL SELECT 'users', count(*) FROM users
UNION ALL SELECT 'bank_accounts', count(*) FROM bank_accounts
UNION ALL SELECT 'vpas', count(*) FROM vpas
UNION ALL SELECT 'merchants', count(*) FROM merchants
UNION ALL SELECT 'transactions', count(*) FROM transactions
UNION ALL SELECT 'rewards', count(*) FROM rewards
UNION ALL SELECT 'bill_payments', count(*) FROM bill_payments
UNION ALL SELECT 'disputes', count(*) FROM disputes
ORDER BY table_name;

DO $$
DECLARE
    bad_count bigint;
BEGIN
    SELECT count(*) INTO bad_count
    FROM users u
    LEFT JOIN cities c ON c.city_id = u.city_id
    WHERE c.city_id IS NULL;
    IF bad_count <> 0 THEN RAISE EXCEPTION 'users.city_id violations: %', bad_count; END IF;

    SELECT count(*) INTO bad_count
    FROM bank_accounts ba
    LEFT JOIN users u ON u.user_id = ba.user_id
    WHERE u.user_id IS NULL;
    IF bad_count <> 0 THEN RAISE EXCEPTION 'bank_accounts.user_id violations: %', bad_count; END IF;

    SELECT count(*) INTO bad_count
    FROM vpas v
    LEFT JOIN bank_accounts ba
      ON ba.account_id = v.account_id AND ba.user_id = v.user_id
    WHERE ba.account_id IS NULL;
    IF bad_count <> 0 THEN RAISE EXCEPTION 'vpas account/user violations: %', bad_count; END IF;

    SELECT count(*) INTO bad_count
    FROM merchants m
    LEFT JOIN cities c ON c.city_id = m.city_id
    WHERE c.city_id IS NULL;
    IF bad_count <> 0 THEN RAISE EXCEPTION 'merchants.city_id violations: %', bad_count; END IF;

    SELECT count(*) INTO bad_count
    FROM transactions t
    LEFT JOIN vpas payer ON payer.vpa = t.payer_vpa
    LEFT JOIN merchants m
      ON m.merchant_id = t.merchant_id
     AND m.merchant_vpa = t.payee_vpa
    WHERE payer.vpa IS NULL
       OR (t.txn_type = 'P2M' AND m.merchant_id IS NULL)
       OR (t.txn_type = 'P2P' AND t.merchant_id IS NOT NULL);
    IF bad_count <> 0 THEN RAISE EXCEPTION 'transactions relationship violations: %', bad_count; END IF;

    SELECT count(*) INTO bad_count
    FROM rewards r
    LEFT JOIN users u ON u.user_id = r.user_id
    LEFT JOIN transactions t ON t.txn_id = r.txn_id
    WHERE u.user_id IS NULL OR t.txn_id IS NULL;
    IF bad_count <> 0 THEN RAISE EXCEPTION 'rewards FK violations: %', bad_count; END IF;

    SELECT count(*) INTO bad_count
    FROM bill_payments b
    LEFT JOIN users u ON u.user_id = b.user_id
    WHERE u.user_id IS NULL;
    IF bad_count <> 0 THEN RAISE EXCEPTION 'bill_payments.user_id violations: %', bad_count; END IF;

    SELECT count(*) INTO bad_count
    FROM disputes d
    LEFT JOIN transactions t ON t.txn_id = d.txn_id
    LEFT JOIN users u ON u.user_id = d.raised_by
    WHERE t.txn_id IS NULL OR u.user_id IS NULL;
    IF bad_count <> 0 THEN RAISE EXCEPTION 'disputes FK violations: %', bad_count; END IF;
END $$;

\echo 'Duplicate primary/natural-key checks'
SELECT 'cities' AS object, count(*) AS duplicate_rows
FROM (SELECT city_id FROM cities GROUP BY city_id HAVING count(*) > 1) d
UNION ALL
SELECT 'users', count(*) FROM (SELECT user_id FROM users GROUP BY user_id HAVING count(*) > 1) d
UNION ALL
SELECT 'phones', count(*) FROM (SELECT phone FROM users GROUP BY phone HAVING count(*) > 1) d
UNION ALL
SELECT 'bank_accounts', count(*) FROM (SELECT account_id FROM bank_accounts GROUP BY account_id HAVING count(*) > 1) d
UNION ALL
SELECT 'vpas', count(*) FROM (SELECT vpa FROM vpas GROUP BY vpa HAVING count(*) > 1) d
UNION ALL
SELECT 'merchants', count(*) FROM (SELECT merchant_id FROM merchants GROUP BY merchant_id HAVING count(*) > 1) d
UNION ALL
SELECT 'merchant_vpas', count(*) FROM (SELECT merchant_vpa FROM merchants GROUP BY merchant_vpa HAVING count(*) > 1) d
UNION ALL
SELECT 'transactions', count(*) FROM (SELECT txn_id FROM transactions GROUP BY txn_id HAVING count(*) > 1) d
UNION ALL
SELECT 'upi_refs', count(*) FROM (SELECT upi_ref FROM transactions GROUP BY upi_ref HAVING count(*) > 1) d
UNION ALL
SELECT 'rewards', count(*) FROM (SELECT reward_id FROM rewards GROUP BY reward_id HAVING count(*) > 1) d
UNION ALL
SELECT 'bill_payments', count(*) FROM (SELECT bill_id FROM bill_payments GROUP BY bill_id HAVING count(*) > 1) d
UNION ALL
SELECT 'disputes', count(*) FROM (SELECT dispute_id FROM disputes GROUP BY dispute_id HAVING count(*) > 1) d;

\echo 'Constraint relationship checks'
SELECT
    sum(CASE WHEN txn_type = 'P2P' AND merchant_id IS NULL THEN 1 ELSE 0 END) AS valid_p2p,
    sum(CASE WHEN txn_type = 'P2M' AND merchant_id IS NOT NULL THEN 1 ELSE 0 END) AS valid_p2m,
    sum(CASE WHEN status = 'FAILED' AND failure_code IS NOT NULL THEN 1 ELSE 0 END) AS valid_failed,
    sum(CASE WHEN status = 'PENDING' AND completed_at IS NULL THEN 1 ELSE 0 END) AS valid_pending
FROM transactions;

\echo 'Integrity verification passed'
