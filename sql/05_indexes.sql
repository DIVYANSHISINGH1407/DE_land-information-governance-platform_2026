SET search_path TO gpay;

-- These help us get a user's UPI IDs quickly for the history, limit,
-- spending, KYC and payment-screen queries.
CREATE INDEX IF NOT EXISTS idx_vpas_user_id_cover
    ON vpas (user_id) INCLUDE (vpa, account_id, is_active);

-- R01: A payment can have the user's VPA as payer or payee, so we need both
-- sides indexed. The time column also helps find the newest payments first.
CREATE INDEX IF NOT EXISTS idx_transactions_payer_time
    ON transactions (payer_vpa, initiated_at DESC)
    INCLUDE (txn_id, upi_ref, payee_vpa, amount, status);
CREATE INDEX IF NOT EXISTS idx_transactions_payee_time
    ON transactions (payee_vpa, initiated_at DESC)
    INCLUDE (txn_id, upi_ref, payer_vpa, amount, status);

-- R23: Read the requested page in newest-first order without sorting every row.
-- It can also help R20 find the month of transactions before grouping by day.
CREATE INDEX IF NOT EXISTS idx_transactions_page_time
    ON transactions (initiated_at DESC)
    INCLUDE (txn_id, upi_ref, txn_type, amount, status);

-- R03 and R14: These queries look up transactions sent from a user's VPA.
-- Keeping the amount in the index also helps with the totals they calculate.
CREATE INDEX IF NOT EXISTS idx_transactions_payer_time_active
    ON transactions (payer_vpa, initiated_at)
    INCLUDE (amount)
    WHERE status IN ('SUCCESS', 'PENDING');

-- R04: Find older pending payments. W02: find the pending payment with the
-- smallest ID so the bank callback can update it.
CREATE INDEX IF NOT EXISTS idx_transactions_pending_time
    ON transactions (initiated_at)
    INCLUDE (txn_id, upi_ref, payer_vpa, amount)
    WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_transactions_pending_txn_id
    ON transactions (txn_id)
    WHERE status = 'PENDING';

-- R05 and R19: Look up payments for one merchant, including its latest one.
CREATE INDEX IF NOT EXISTS idx_transactions_merchant_time
    ON transactions (merchant_id, initiated_at DESC)
    INCLUDE (status, amount)
    WHERE merchant_id IS NOT NULL;

-- R06 and R15: These use successful payments over a date range for settlement
-- and merchant totals. R20 uses the broader date index defined above because
-- it counts every status, not only successful payments.
CREATE INDEX IF NOT EXISTS idx_transactions_success_time
    ON transactions (initiated_at)
    INCLUDE (merchant_id, amount)
    WHERE status = 'SUCCESS';

-- R07: Narrow down recent failed payments before grouping by bank and code.
CREATE INDEX IF NOT EXISTS idx_transactions_failed_time
    ON transactions (initiated_at)
    INCLUDE (payer_vpa, failure_code)
    WHERE status = 'FAILED';

-- R09: Keep successful payments in payer/payee/time order for the repeat check.
-- R14 and R18 can also use the payer part of this index for their joins.
CREATE INDEX IF NOT EXISTS idx_transactions_success_pair_time
    ON transactions (payer_vpa, payee_vpa, initiated_at)
    INCLUDE (amount)
    WHERE status = 'SUCCESS';
-- R08: Group P2P payments by recipient and day, with payer and amount ready.
CREATE INDEX IF NOT EXISTS idx_transactions_success_p2p_day
    ON transactions (payee_vpa, initiated_at)
    INCLUDE (payer_vpa, amount)
    WHERE txn_type = 'P2P' AND status = 'SUCCESS';

-- R13: Skip P2P rows that have no merchant when checking merchant activity.
-- R17: Keep the merchant and status values handy for the P2M refund report.
CREATE INDEX IF NOT EXISTS idx_transactions_merchant_id_present
    ON transactions (merchant_id)
    WHERE merchant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_transactions_p2m_merchant_status
    ON transactions (merchant_id)
    INCLUDE (status)
    WHERE txn_type = 'P2M';

-- R25: This keeps the payer and completion time alongside the date so the
-- bank-latency report can read the values it needs from the index.
CREATE INDEX IF NOT EXISTS idx_transactions_completed_time
    ON transactions (initiated_at)
    INCLUDE (payer_vpa, completed_at)
    WHERE completed_at IS NOT NULL;

-- R10 and W03: Find a user's active scratch cards by expiry, and find their
-- oldest unscratched card when they scratch one.
CREATE INDEX IF NOT EXISTS idx_rewards_unscratched_user_expiry
    ON rewards (user_id, expires_at)
    INCLUDE (reward_id, reward_type, issued_at)
    WHERE status = 'UNSCRATCHED';
CREATE INDEX IF NOT EXISTS idx_rewards_unscratched_user_id
    ON rewards (user_id, reward_id)
    WHERE status = 'UNSCRATCHED';

-- R11 and W04: The reminder and expiry job only need cards that are still
-- unscratched, starting with the ones that expire soonest.
CREATE INDEX IF NOT EXISTS idx_rewards_unscratched_expiry
    ON rewards (expires_at)
    INCLUDE (reward_id, user_id)
    WHERE status = 'UNSCRATCHED';

-- R12 and W05: Find one user's upcoming bills, or all bills past their due date.
CREATE INDEX IF NOT EXISTS idx_bills_due_user_date
    ON bill_payments (user_id, due_date)
    INCLUDE (bill_id, biller_name, amount)
    WHERE status = 'DUE';
CREATE INDEX IF NOT EXISTS idx_bills_due_date
    ON bill_payments (due_date)
    WHERE status = 'DUE';

-- R16: The SLA report only checks disputes that are still open.
CREATE INDEX IF NOT EXISTS idx_disputes_open_raised_at
    ON disputes (raised_at)
    INCLUDE (dispute_id, txn_id, reason)
    WHERE status = 'OPEN';

-- R21: A regular index can't search for text in the middle of a name;
-- pg_trgm lets this index help with the '%chai%' search.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_merchants_name_trgm
    ON merchants USING gin (merchant_name gin_trgm_ops);

ANALYZE;
