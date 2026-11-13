# CP1 — Schema Design and Normalization

## Source data and design approach

The schema was derived from the nine supplied CSV files. The staged loader reads each CSV into temporary text columns first, then inserts typed values into the final tables in one transaction. Blank fields are converted to SQL `NULL` only for columns that are nullable in the source data. A CSV parsing error, invalid cast, or constraint violation stops the load; the final-table inserts roll back and the original files are never edited.

The project brief's row counts were confirmed against the loaded data:

| Table | CSV rows | Loaded rows |
|---|---:|---:|
| `cities` | 10 | 10 |
| `users` | 40,000 | 40,000 |
| `bank_accounts` | 53,333 | 53,333 |
| `vpas` | 53,333 | 53,333 |
| `merchants` | 3,000 | 3,000 |
| `transactions` | 250,468 | 250,468 |
| `rewards` | 39,799 | 39,799 |
| `bill_payments` | 30,000 | 30,000 |
| `disputes` | 3,569 | 3,569 |

## Entity and relationship overview

The diagram source is [er_diagram.mmd](../diagrams/er_diagram.mmd); an SVG rendering is [er_diagram.svg](../diagrams/er_diagram.svg).

| Relationship | Cardinality / rule |
|---|---|
| `cities` → `users` | One city can have many users; each user references one city. |
| `cities` → `merchants` | One city can have many merchants; each merchant references one city. |
| `users` → `bank_accounts` | One user can have multiple accounts; each account belongs to one user. |
| `users` → `vpas` | One user can have multiple VPAs; each VPA belongs to one user. |
| `bank_accounts` → `vpas` | Each VPA references an account owned by the same user. |
| `vpas` → `transactions` | A VPA can be the payer on many transactions; each transaction has one local payer VPA. |
| `merchants` → `transactions` | A merchant can receive many P2M payments. P2P transactions have no merchant. |
| `users` / `transactions` → `rewards` | A user and a transaction can each be associated with rewards. The schema allows multiple rewards per transaction. |
| `users` → `bill_payments` | One user can have many bills. |
| `users` / `transactions` → `disputes` | Each dispute references one raising user and one transaction; each may be referenced by multiple disputes. |

The 16,583 P2P payee VPAs not found in the local `vpas` export are external recipients. They are intentionally not constrained as local VPA foreign keys. For P2M, the composite foreign key `(merchant_id, payee_vpa)` enforces that the payee is the selected merchant's VPA.

## Data dictionary

`NOT NULL` is shown as **required**. Primary keys and foreign keys are listed separately below; each row also notes its principal validation.

### `cities` — city reference data

| Column | Type | Required | Key / validation | Meaning |
|---|---|---|---|---|
| `city_id` | `integer` | Yes | PK; positive | Source city identifier. |
| `city_name` | `text` | Yes | — | City name. |
| `state` | `text` | Yes | — | State or territory name. |

### `users` — registered users

| Column | Type | Required | Key / validation | Meaning |
|---|---|---|---|---|
| `user_id` | `integer` | Yes | PK; positive | Source user identifier. |
| `full_name` | `text` | Yes | — | User's displayed name. |
| `phone` | `varchar(10)` | Yes | UNIQUE; ten digits | Phone number; unique in the export. |
| `email` | `text` | No | UNIQUE when present | Optional email; 15,950 rows are blank. |
| `city_id` | `integer` | Yes | FK → `cities.city_id` | User's city. |
| `kyc_status` | `text` | Yes | `PENDING`, `VERIFIED`, `REJECTED` | KYC state observed in the export. |
| `is_blocked` | `boolean` | Yes | — | Whether the account is blocked. |
| `created_at` | `timestamptz` | Yes | — | Account creation time, including source offset. |

### `bank_accounts` — accounts linked by users

| Column | Type | Required | Key / validation | Meaning |
|---|---|---|---|---|
| `account_id` | `integer` | Yes | PK; positive | Source account identifier. |
| `user_id` | `integer` | Yes | FK → `users.user_id` | Account owner. |
| `bank_name` | `text` | Yes | — | Bank name from the export. |
| `ifsc` | `varchar(11)` | Yes | Eleven-character IFSC pattern | IFSC code. |
| `account_last4` | `varchar(4)` | Yes | Four digits | Redacted account suffix; text preserves leading zeros. |
| `account_type` | `text` | Yes | `SAVINGS` or `CURRENT` | Account type. |
| `is_primary` | `boolean` | Yes | — | Whether this is the user's primary account. |
| `linked_at` | `timestamptz` | Yes | — | Account-link time, including source offset. |

### `vpas` — virtual payment addresses

| Column | Type | Required | Key / validation | Meaning |
|---|---|---|---|---|
| `vpa` | `text` | Yes | PK; non-whitespace local-part and domain separated by `@` | UPI address. |
| `user_id` | `integer` | Yes | FK → `users.user_id`; composite ownership FK | User associated with the VPA. |
| `account_id` | `integer` | Yes | Composite FK with `user_id` → `bank_accounts` | Linked bank account. |
| `is_active` | `boolean` | Yes | — | Whether the VPA is active. |
| `created_at` | `timestamptz` | Yes | — | VPA creation time. |

### `merchants` — businesses accepting payments

| Column | Type | Required | Key / validation | Meaning |
|---|---|---|---|---|
| `merchant_id` | `integer` | Yes | PK; positive | Source merchant identifier. |
| `merchant_name` | `text` | Yes | — | Business name. |
| `mcc` | `smallint` | Yes | Four-digit range, 1000–9999 | Merchant category code. |
| `merchant_vpa` | `text` | Yes | UNIQUE; VPA format | Merchant's UPI address. |
| `city_id` | `integer` | Yes | FK → `cities.city_id` | Merchant's city. |
| `is_verified` | `boolean` | Yes | — | Merchant verification flag. |
| `onboarded_on` | `date` | Yes | — | Merchant onboarding date. |

### `transactions` — P2P and P2M payment records

| Column | Type | Required | Key / validation | Meaning |
|---|---|---|---|---|
| `txn_id` | `integer` | Yes | PK; positive | Source transaction identifier. |
| `upi_ref` | `varchar(12)` | Yes | UNIQUE; exactly 12 digits | UPI reference number. |
| `txn_type` | `text` | Yes | `P2P` or `P2M` | Payment category. |
| `payer_vpa` | `text` | Yes | FK → `vpas.vpa` | Local payer address. |
| `payee_vpa` | `text` | Yes | For P2M, composite FK with `merchant_id` | Recipient address; P2P recipients may be external. |
| `merchant_id` | `integer` | No | Nullable composite FK; required exactly for P2M | Merchant recipient; absent for P2P. |
| `amount` | `numeric(12,2)` | Yes | Positive | Payment amount. |
| `note` | `text` | No | — | Optional payment note; 175,013 rows are blank. |
| `initiated_at` | `timestamptz` | Yes | — | Payment initiation time. |
| `completed_at` | `timestamptz` | No | Required except for `PENDING`; not before initiation | Completion time; blank for 125 pending payments. |
| `status` | `text` | Yes | `SUCCESS`, `FAILED`, `REVERSED`, `REFUNDED`, `PENDING` | Payment outcome. |
| `failure_code` | `text` | No | `U16`, `U30`, `U69`, `XH`, `Z9`, `ZM`; present only for `FAILED` | Failure reason code; 238,077 rows are blank. |

### `rewards` — reward and cashback records

| Column | Type | Required | Key / validation | Meaning |
|---|---|---|---|---|
| `reward_id` | `integer` | Yes | PK; positive | Source reward identifier. |
| `user_id` | `integer` | Yes | FK → `users.user_id` | User associated with the reward. |
| `txn_id` | `integer` | Yes | FK → `transactions.txn_id` | Related transaction. |
| `reward_type` | `text` | Yes | `SCRATCH_CARD`, `CASHBACK`, `COUPON` | Reward category. |
| `amount` | `numeric(8,2)` | Yes | Nonnegative | Reward amount. |
| `status` | `text` | Yes | `CREDITED`, `EXPIRED`, `UNSCRATCHED` | Reward state. |
| `issued_at` | `timestamptz` | Yes | — | Issue time. |
| `expires_at` | `timestamptz` | Yes | Not before issue | Expiry time. |
| `credited_at` | `timestamptz` | No | Present exactly when status is `CREDITED` | Credit time; blank for expired or unscratched rewards (8,054 rows). |

### `bill_payments` — utility and recharge bills

| Column | Type | Required | Key / validation | Meaning |
|---|---|---|---|---|
| `bill_id` | `integer` | Yes | PK; positive | Source bill identifier. |
| `user_id` | `integer` | Yes | FK → `users.user_id` | Bill owner. |
| `biller_category` | `text` | Yes | One of seven observed categories | Bill category. |
| `biller_name` | `text` | Yes | — | Biller name. |
| `consumer_number` | `text` | Yes | — | Consumer/account identifier; text preserves leading zeros. |
| `amount` | `numeric(10,2)` | Yes | Positive | Bill amount. |
| `due_date` | `date` | Yes | — | Due date. |
| `status` | `text` | Yes | `DUE`, `OVERDUE`, `PAID` | Bill state. |
| `paid_at` | `timestamptz` | No | Present exactly when status is `PAID` | Payment time; blank for unpaid bills (4,338 rows). |

### `disputes` — customer-raised payment disputes

| Column | Type | Required | Key / validation | Meaning |
|---|---|---|---|---|
| `dispute_id` | `integer` | Yes | PK; positive | Source dispute identifier. |
| `txn_id` | `integer` | Yes | FK → `transactions.txn_id` | Disputed transaction. |
| `raised_by` | `integer` | Yes | FK → `users.user_id` | User who raised the dispute. |
| `reason` | `text` | Yes | One of five observed reasons | Dispute reason. |
| `raised_at` | `timestamptz` | Yes | — | Dispute creation time. |
| `status` | `text` | Yes | `OPEN`, `RESOLVED`, `REJECTED` | Dispute state. |
| `resolved_at` | `timestamptz` | No | Null only while `OPEN`; not before `raised_at` | Resolution time; blank for 116 open disputes. |

## Keys and delete behavior

All nine tables have a primary key. The natural/alternate unique keys are `users.phone`, non-null `users.email`, `merchants.merchant_vpa`, and `transactions.upi_ref`. The schema also has unique composite keys on `bank_accounts(account_id, user_id)` and `merchants(merchant_id, merchant_vpa)` to support ownership and merchant/payee foreign keys. PostgreSQL creates indexes for primary and unique constraints; **no additional or performance-tuning indexes** were created.

Foreign keys use `ON DELETE RESTRICT` so referenced users, accounts, VPAs, merchants, and payment history cannot be deleted while dependent records remain. The P2M composite foreign key checks both the merchant identifier and payee address. P2P recipients are intentionally not foreign-keyed because some belong to other UPI apps.

The schema defines **39 CHECK constraints**, including allowed-value lists, identifier formats, positive/nonnegative amounts, transaction type/merchant consistency, failure/completion timestamp consistency, and status/timestamp consistency for rewards, bills, and disputes.

## Functional dependencies and normal-form analysis

All source columns are atomic in the loaded rows, so the relations satisfy 1NF. There are no composite primary keys, so there are no partial dependencies and the relations satisfy 2NF. The principal key dependencies are:

| Relation | Functional dependencies supported by declared keys |
|---|---|
| `cities` | `city_id → city_name, state` |
| `users` | `user_id → full_name, phone, email, city_id, kyc_status, is_blocked, created_at`; `phone → user_id, …`; non-null `email → user_id, …` |
| `bank_accounts` | `account_id → user_id, bank_name, ifsc, account_last4, account_type, is_primary, linked_at` |
| `vpas` | `vpa → user_id, account_id, is_active, created_at` |
| `merchants` | `merchant_id → merchant_name, mcc, merchant_vpa, city_id, is_verified, onboarded_on`; `merchant_vpa → merchant_id, …` |
| `transactions` | `txn_id → upi_ref, txn_type, payer_vpa, payee_vpa, merchant_id, amount, note, initiated_at, completed_at, status, failure_code`; `upi_ref → txn_id, …` |
| `rewards` | `reward_id → user_id, txn_id, reward_type, amount, status, issued_at, expires_at, credited_at` |
| `bill_payments` | `bill_id → user_id, biller_category, biller_name, consumer_number, amount, due_date, status, paid_at` |
| `disputes` | `dispute_id → txn_id, raised_by, reason, raised_at, status, resolved_at` |

With the dependencies implied by the exported relationships included, `cities`, `users`, `bank_accounts`, `merchants`, `bill_payments`, and `disputes` are in 3NF/BCNF: their nontrivial determinants are candidate keys. Three tables retain dependencies on non-key attributes and are therefore intentional 3NF/BCNF exceptions:

* In `vpas`, the referenced `bank_accounts.account_id → user_id` means `account_id → vpas.user_id` as well. Since `vpas.account_id` is not declared unique, it is not a candidate key in this relation. `vpas.user_id` is retained because it is a source column used by the supplied workload; a composite foreign key requires the VPA user and bank-account owner to match.
* For P2M rows in `transactions`, `merchant_id → payee_vpa` because each merchant has one unique VPA. `merchant_id` is not a transaction key. The payee address is retained for the payment record and supplied queries; a composite foreign key enforces equality with the selected merchant.
* In `rewards`, `txn_id → user_id` through the related transaction's payer VPA and its owner. `user_id` is retained for the supplied workload's direct user-based reward lookup. This cross-table dependency is not enforceable by a normal foreign key; the loaded rows are checked below. A future redesign could derive it through transaction and VPA joins, but would need to preserve the unchanged workload interface.

These columns are documented compatibility/traceability exceptions rather than claims that the duplicated facts are necessary in an idealized model. The checked seed data has one VPA per account and one reward per transaction, but the schema does not enforce either as a permanent business rule. A strict 3NF redesign would remove the duplicated attributes and adjust the query interface; CP1 instead keeps every source column required by the unchanged workload.

## Integrity checks performed after loading

All counts below were queried from PostgreSQL after the successful load:

| Check | Result |
|---|---:|
| Expected row counts for all nine tables | Match exactly (see table above). |
| P2M payee VPA equals the selected merchant's VPA | 139,887 match; 0 mismatches. |
| VPA user equals linked bank-account owner | 53,333 match; 0 mismatches. |
| Reward user equals the owner of the related transaction's payer VPA | 39,799 match; 0 mismatches. |
| Users with exactly one primary bank account | 40,000. |
| P2P payee VPAs absent from local `vpas` | 16,583; treated as external recipients, not bad foreign keys. |
| CHECK constraints installed | 39. |

## Data-quality observations and assumptions

* CSV empty fields were preserved as SQL `NULL` where the column is optional. Notable missing values are email (15,950), transaction note (175,013), transaction merchant ID (110,581 P2P rows), completion time (125 pending transactions), failure code (238,077 non-failed transactions), reward credit time (8,054), bill paid time (4,338), and dispute resolution time (116 open disputes).
* All failed transactions have one of the six observed failure codes; other statuses have no failure code. Pending transactions have no completion timestamp; all other transaction statuses have one.
* Phone numbers, account suffixes, and consumer numbers are stored as text where needed to preserve formatting/leading zeros. Monetary values use fixed-precision `numeric`; timestamps with offsets use `timestamptz`.
* The supplied CSVs parsed successfully, and all values passed casts and constraints. No source CSV was rewritten.
* One primary account per user is verified as a dataset invariant. It is not enforced by an additional partial unique index because CP1 prohibits adding non-constraint tuning indexes; PostgreSQL has no ordinary table CHECK constraint that can enforce this cross-row rule.
* The source files are treated as the authority for observed value domains. No unstated UPI transaction cap, email format policy, or uniqueness rule for consumer numbers was added.
