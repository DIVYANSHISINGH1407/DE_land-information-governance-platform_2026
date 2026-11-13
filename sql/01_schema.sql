CREATE SCHEMA gpay;
SET search_path TO gpay;

CREATE TABLE cities (
    city_id integer PRIMARY KEY,
    city_name text NOT NULL,
    state text NOT NULL,
    CONSTRAINT cities_city_id_positive CHECK (city_id > 0)
);

CREATE TABLE users (
    user_id integer PRIMARY KEY,
    full_name text NOT NULL,
    phone varchar(10) NOT NULL UNIQUE,
    email text UNIQUE,
    city_id integer NOT NULL REFERENCES cities (city_id) ON DELETE RESTRICT,
    kyc_status text NOT NULL,
    is_blocked boolean NOT NULL,
    created_at timestamptz NOT NULL,
    CONSTRAINT users_user_id_positive CHECK (user_id > 0),
    CONSTRAINT users_phone_format CHECK (phone ~ '^[0-9]{10}$'),
    CONSTRAINT users_kyc_status CHECK (kyc_status IN ('PENDING', 'VERIFIED', 'REJECTED'))
);

CREATE TABLE bank_accounts (
    account_id integer PRIMARY KEY,
    user_id integer NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    bank_name text NOT NULL,
    ifsc varchar(11) NOT NULL,
    account_last4 varchar(4) NOT NULL,
    account_type text NOT NULL,
    is_primary boolean NOT NULL,
    linked_at timestamptz NOT NULL,
    CONSTRAINT bank_accounts_account_id_positive CHECK (account_id > 0),
    CONSTRAINT bank_accounts_user_account_unique UNIQUE (account_id, user_id),
    CONSTRAINT bank_accounts_ifsc_format CHECK (ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
    CONSTRAINT bank_accounts_last4_format CHECK (account_last4 ~ '^[0-9]{4}$'),
    CONSTRAINT bank_accounts_account_type CHECK (account_type IN ('SAVINGS', 'CURRENT'))
);

CREATE TABLE vpas (
    vpa text PRIMARY KEY,
    user_id integer NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    account_id integer NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamptz NOT NULL,
    CONSTRAINT vpas_vpa_format CHECK (vpa ~ '^[^[:space:]@]+@[^[:space:]@]+$'),
    CONSTRAINT vpas_account_user_fk
        FOREIGN KEY (account_id, user_id)
        REFERENCES bank_accounts (account_id, user_id)
        ON DELETE RESTRICT
);

CREATE TABLE merchants (
    merchant_id integer PRIMARY KEY,
    merchant_name text NOT NULL,
    mcc smallint NOT NULL,
    merchant_vpa text NOT NULL UNIQUE,
    city_id integer NOT NULL REFERENCES cities (city_id) ON DELETE RESTRICT,
    is_verified boolean NOT NULL,
    onboarded_on date NOT NULL,
    CONSTRAINT merchants_merchant_id_positive CHECK (merchant_id > 0),
    CONSTRAINT merchants_mcc_four_digits CHECK (mcc BETWEEN 1000 AND 9999),
    CONSTRAINT merchants_vpa_format CHECK (merchant_vpa ~ '^[^[:space:]@]+@[^[:space:]@]+$'),
    CONSTRAINT merchants_id_vpa_unique UNIQUE (merchant_id, merchant_vpa)
);

CREATE TABLE transactions (
    txn_id integer PRIMARY KEY,
    upi_ref varchar(12) NOT NULL UNIQUE,
    txn_type text NOT NULL,
    payer_vpa text NOT NULL REFERENCES vpas (vpa) ON DELETE RESTRICT,
    payee_vpa text NOT NULL,
    merchant_id integer,
    amount numeric(12, 2) NOT NULL,
    note text,
    initiated_at timestamptz NOT NULL,
    completed_at timestamptz,
    status text NOT NULL,
    failure_code text,
    CONSTRAINT transactions_txn_id_positive CHECK (txn_id > 0),
    CONSTRAINT transactions_upi_ref_format CHECK (upi_ref ~ '^[0-9]{12}$'),
    CONSTRAINT transactions_type CHECK (txn_type IN ('P2P', 'P2M')),
    CONSTRAINT transactions_amount_positive CHECK (amount > 0),
    CONSTRAINT transactions_status CHECK (status IN ('SUCCESS', 'FAILED', 'REVERSED', 'REFUNDED', 'PENDING')),
    CONSTRAINT transactions_failure_code CHECK (failure_code IS NULL OR failure_code IN ('U16', 'U30', 'U69', 'XH', 'Z9', 'ZM')),
    CONSTRAINT transactions_failure_status_match CHECK (
        (status = 'FAILED' AND failure_code IS NOT NULL)
        OR (status <> 'FAILED' AND failure_code IS NULL)
    ),
    CONSTRAINT transactions_completion_status_match CHECK (
        (status = 'PENDING' AND completed_at IS NULL)
        OR (status <> 'PENDING' AND completed_at IS NOT NULL)
    ),
    CONSTRAINT transactions_completion_after_initiation CHECK (
        completed_at IS NULL OR completed_at >= initiated_at
    ),
    CONSTRAINT transactions_type_merchant_match CHECK (
        (txn_type = 'P2M' AND merchant_id IS NOT NULL)
        OR (txn_type = 'P2P' AND merchant_id IS NULL)
    ),
    CONSTRAINT transactions_refund_is_p2m CHECK (status <> 'REFUNDED' OR txn_type = 'P2M'),
    CONSTRAINT transactions_merchant_payee_fk
        FOREIGN KEY (merchant_id, payee_vpa)
        REFERENCES merchants (merchant_id, merchant_vpa)
        ON DELETE RESTRICT
);

CREATE TABLE rewards (
    reward_id integer PRIMARY KEY,
    user_id integer NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    txn_id integer NOT NULL REFERENCES transactions (txn_id) ON DELETE RESTRICT,
    reward_type text NOT NULL,
    amount numeric(8, 2) NOT NULL,
    status text NOT NULL,
    issued_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    credited_at timestamptz,
    CONSTRAINT rewards_reward_id_positive CHECK (reward_id > 0),
    CONSTRAINT rewards_type CHECK (reward_type IN ('SCRATCH_CARD', 'CASHBACK', 'COUPON')),
    CONSTRAINT rewards_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT rewards_status CHECK (status IN ('CREDITED', 'EXPIRED', 'UNSCRATCHED')),
    CONSTRAINT rewards_credit_status_match CHECK (
        (status = 'CREDITED' AND credited_at IS NOT NULL)
        OR (status <> 'CREDITED' AND credited_at IS NULL)
    ),
    CONSTRAINT rewards_expiry_after_issue CHECK (expires_at >= issued_at)
);

CREATE TABLE bill_payments (
    bill_id integer PRIMARY KEY,
    user_id integer NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    biller_category text NOT NULL,
    biller_name text NOT NULL,
    consumer_number text NOT NULL,
    amount numeric(10, 2) NOT NULL,
    due_date date NOT NULL,
    status text NOT NULL,
    paid_at timestamptz,
    CONSTRAINT bill_payments_bill_id_positive CHECK (bill_id > 0),
    CONSTRAINT bill_payments_category CHECK (
        biller_category IN ('BROADBAND', 'DTH', 'ELECTRICITY', 'FASTAG', 'GAS', 'MOBILE', 'WATER')
    ),
    CONSTRAINT bill_payments_amount_positive CHECK (amount > 0),
    CONSTRAINT bill_payments_status CHECK (status IN ('DUE', 'OVERDUE', 'PAID')),
    CONSTRAINT bill_payments_paid_status_match CHECK (
        (status = 'PAID' AND paid_at IS NOT NULL)
        OR (status <> 'PAID' AND paid_at IS NULL)
    )
);

CREATE TABLE disputes (
    dispute_id integer PRIMARY KEY,
    txn_id integer NOT NULL REFERENCES transactions (txn_id) ON DELETE RESTRICT,
    raised_by integer NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    reason text NOT NULL,
    raised_at timestamptz NOT NULL,
    status text NOT NULL,
    resolved_at timestamptz,
    CONSTRAINT disputes_dispute_id_positive CHECK (dispute_id > 0),
    CONSTRAINT disputes_reason CHECK (
        reason IN ('DUPLICATE_PAYMENT', 'FRAUD', 'MERCHANT_NOT_DELIVERED', 'MONEY_DEBITED_NOT_CREDITED', 'WRONG_PAYEE')
    ),
    CONSTRAINT disputes_status CHECK (status IN ('OPEN', 'RESOLVED', 'REJECTED')),
    CONSTRAINT disputes_resolution_status_match CHECK (
        (status = 'OPEN' AND resolved_at IS NULL)
        OR (status IN ('RESOLVED', 'REJECTED') AND resolved_at IS NOT NULL)
    ),
    CONSTRAINT disputes_resolution_after_raised CHECK (
        resolved_at IS NULL OR resolved_at >= raised_at
    )
);
