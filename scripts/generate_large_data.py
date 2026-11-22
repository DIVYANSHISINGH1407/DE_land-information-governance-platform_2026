#!/usr/bin/env python3
"""Generate a deterministic, approximately 20x gpay dataset.

The generated data is derived only from seed_data/*.csv. Seed files are never
modified. Existing seed rows are copied once; synthetic rows receive new IDs
and valid references to the generated parent rows.
"""

import argparse
import csv
import shutil
import tempfile
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path


SCALE = 20
TARGET_USERS = 800_000
TARGET_ACCOUNTS = 53_333 * SCALE
TARGET_MERCHANTS = 60_000

TABLE_FILES = {
    "cities": "cities.csv",
    "users": "users.csv",
    "bank_accounts": "bank_accounts.csv",
    "vpas": "vpas.csv",
    "merchants": "merchants.csv",
    "transactions": "transactions.csv",
    "rewards": "rewards.csv",
    "bill_payments": "bill_payments.csv",
    "disputes": "disputes.csv",
}


def read_csv(path):
    with path.open("r", newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        return reader.fieldnames, list(reader)


def atomic_write_csv(folder, name, fieldnames, rows):
    path = folder / name
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def max_id(rows, column):
    return max(int(row[column]) for row in rows)


def timestamp(seconds):
    return (datetime(2025, 1, 1, 0, 0, 0) + timedelta(seconds=seconds)).strftime(
        "%Y-%m-%d %H:%M:%S+05:30"
    )


def generate(root, output):
    seed = root / "seed_data"
    data = {}
    fields = {}

    for table, filename in TABLE_FILES.items():
        fields[table], data[table] = read_csv(seed / filename)

    original_counts = {table: len(rows) for table, rows in data.items()}
    output.mkdir(parents=True, exist_ok=True)

    staging = Path(tempfile.mkdtemp(prefix=".large_data-", dir=output.parent))

    try:
        # Cities are dimensions; keep the existing 10 city records.
        atomic_write_csv(staging, "cities.csv", fields["cities"], data["cities"])

        # Users
        users = list(data["users"])
        next_user_id = max_id(users, "user_id") + 1
        for user_id in range(next_user_id, TARGET_USERS + 1):
            phone = str(910_000_0000 + user_id - next_user_id)
            users.append({
                "user_id": str(user_id),
                "full_name": f"Generated User {user_id}",
                "phone": phone,
                "email": f"generated.user.{user_id}@example.com",
                "city_id": str(((user_id - 1) % 10) + 1),
                "kyc_status": ("VERIFIED" if user_id % 10 else "PENDING"),
                "is_blocked": ("t" if user_id % 50 == 0 else "f"),
                "created_at": timestamp((user_id - 40001) * 60),
            })
        atomic_write_csv(staging, "users.csv", fields["users"], users)

        # Bank accounts
        accounts = list(data["bank_accounts"])
        next_account_id = max_id(accounts, "account_id") + 1
        target_account_count = TARGET_ACCOUNTS
        synthetic_account_count = target_account_count - len(accounts)
        account_ids = set(int(row["account_id"]) for row in accounts)
        account_id = next_account_id
        for index in range(synthetic_account_count):
            while account_id in account_ids:
                account_id += 1
            account_ids.add(account_id)
            user_id = (index % TARGET_USERS) + 1
            accounts.append({
                "account_id": str(account_id),
                "user_id": str(user_id),
                "bank_name": ("HDFC Bank" if index % 4 == 0 else
                              "ICICI Bank" if index % 4 == 1 else
                              "SBI" if index % 4 == 2 else "Axis Bank"),
                "ifsc": f"BANK0{(index % 1000000):06d}",
                "account_last4": f"{index % 10000:04d}",
                "account_type": ("SAVINGS" if index % 5 else "CURRENT"),
                "is_primary": ("t" if index < TARGET_USERS else "f"),
                "linked_at": timestamp(index * 37),
            })
            account_id += 1
        atomic_write_csv(staging, "bank_accounts.csv", fields["bank_accounts"], accounts)

        # VPAs
        vpas = list(data["vpas"])
        original_account_by_vpa = {
            int(row["account_id"]): int(row["user_id"]) for row in vpas
        }
        synthetic_accounts = accounts[len(data["bank_accounts"]):]
        for index, account in enumerate(synthetic_accounts):
            vpa_name = f"generated{int(account['account_id'])}"
            vpas.append({
                "vpa": f"{vpa_name}@okaxis",
                "user_id": account["user_id"],
                "account_id": account["account_id"],
                "is_active": ("t" if index % 20 else "f"),
                "created_at": account["linked_at"],
            })
        atomic_write_csv(staging, "vpas.csv", fields["vpas"], vpas)

        # Merchants
        merchants = list(data["merchants"])
        next_merchant_id = max_id(merchants, "merchant_id") + 1
        for merchant_id in range(next_merchant_id, TARGET_MERCHANTS + 1):
            merchants.append({
                "merchant_id": str(merchant_id),
                "merchant_name": f"Generated Store {merchant_id}",
                "mcc": str(1000 + (merchant_id % 9000)),
                "merchant_vpa": f"merchant{merchant_id}@okbizaxis",
                "city_id": str(((merchant_id - 1) % 10) + 1),
                "is_verified": ("t" if merchant_id % 4 else "f"),
                "onboarded_on": (date(2018, 1, 1) +
                                 timedelta(days=(merchant_id % 3000))).isoformat(),
            })
        atomic_write_csv(staging, "merchants.csv", fields["merchants"], merchants)

        # Transactions
        transactions = list(data["transactions"])
        next_txn_id = max_id(transactions, "txn_id") + 1
        target_txn_count = len(data["transactions"]) * SCALE
        synthetic_txn_count = target_txn_count - len(transactions)
        payer_vpas = [row["vpa"] for row in vpas]
        merchant_vpas = [row["merchant_vpa"] for row in merchants]
        merchant_ids = [int(row["merchant_id"]) for row in merchants]
        used_upi_refs = {row["upi_ref"] for row in transactions}
        for offset in range(synthetic_txn_count):
            txn_id = next_txn_id + offset
            upi_ref = str(900_000_000_000 + txn_id)
            while upi_ref in used_upi_refs:
                upi_ref = str(int(upi_ref) + 1)
            used_upi_refs.add(upi_ref)
            payer_index = (txn_id * 17) % len(payer_vpas)
            payer_vpa = payer_vpas[payer_index]
            is_p2m = offset % 10 < 7
            if is_p2m:
                merchant_index = (txn_id * 29) % len(merchants)
                txn_type = "P2M"
                merchant_id = merchant_ids[merchant_index]
                payee_vpa = merchant_vpas[merchant_index]
            else:
                txn_type = "P2P"
                merchant_id = ""
                payee_index = (payer_index + 1 + (txn_id % 97)) % len(payer_vpas)
                payee_vpa = payer_vpas[payee_index]
                if payee_vpa == payer_vpa:
                    payee_vpa = payer_vpas[(payee_index + 1) % len(payer_vpas)]

            status_roll = offset % 100
            if status_roll < 82:
                status = "SUCCESS"
                failure_code = ""
            elif status_roll < 89:
                status = "FAILED"
                failure_code = ("U16", "U30", "U69", "XH", "Z9", "ZM")[offset % 6]
            elif status_roll < 93:
                status = "REVERSED"
                failure_code = ""
            elif status_roll < 97:
                status = "REFUNDED" if is_p2m else "SUCCESS"
                failure_code = ""
            else:
                status = "PENDING"
                failure_code = ""

            initiated = timestamp(offset * 9)
            if status == "PENDING":
                completed = ""
            elif status in ("SUCCESS", "FAILED"):
                seconds = 3 + (offset % 57)
                dt = datetime(2025, 1, 1, 0, 0, 0) + timedelta(seconds=offset * 9 + seconds)
                completed = dt.strftime("%Y-%m-%d %H:%M:%S+05:30")
            else:
                dt = datetime(2025, 1, 1, 0, 0, 0) + timedelta(seconds=offset * 9 + 300 + offset % 3600)
                completed = dt.strftime("%Y-%m-%d %H:%M:%S+05:30")

            transactions.append({
                "txn_id": str(txn_id),
                "upi_ref": upi_ref,
                "txn_type": txn_type,
                "payer_vpa": payer_vpa,
                "payee_vpa": payee_vpa,
                "merchant_id": merchant_id,
                "amount": f"{(100 + (txn_id % 250000) + (txn_id % 100) / 100):.2f}",
                "note": "" if offset % 4 else f"Generated payment {txn_id}",
                "initiated_at": initiated,
                "completed_at": completed,
                "status": status,
                "failure_code": failure_code,
            })
        atomic_write_csv(staging, "transactions.csv", fields["transactions"], transactions)

        # Rewards
        rewards = list(data["rewards"])
        next_reward_id = max_id(rewards, "reward_id") + 1
        target_reward_count = len(rewards) * SCALE
        synthetic_reward_count = target_reward_count - len(rewards)
        txn_count = len(transactions)
        for offset in range(synthetic_reward_count):
            reward_id = next_reward_id + offset
            issued_seconds = offset * 62
            issued = timestamp(issued_seconds)
            expires_dt = datetime(2025, 1, 1, 0, 0, 0) + timedelta(
                seconds=issued_seconds + 30 * 86400
            )
            expires = expires_dt.strftime("%Y-%m-%d %H:%M:%S+05:30")
            status_roll = offset % 10
            status = "CREDITED" if status_roll < 6 else "UNSCRATCHED" if status_roll < 9 else "EXPIRED"
            credited = ""
            if status == "CREDITED":
                credited_dt = datetime(2025, 1, 1, 0, 0, 0) + timedelta(seconds=issued_seconds + 3600)
                credited = credited_dt.strftime("%Y-%m-%d %H:%M:%S+05:30")
            txn_index = (offset * 3571) % txn_count
            rewards.append({
                "reward_id": str(reward_id),
                "user_id": str((offset % TARGET_USERS) + 1),
                "txn_id": str(int(transactions[txn_index]["txn_id"])),
                "reward_type": ("SCRATCH_CARD" if offset % 3 == 0 else
                                "CASHBACK" if offset % 3 == 1 else "COUPON"),
                "amount": f"{(offset % 500) / 100:.2f}",
                "status": status,
                "issued_at": issued,
                "expires_at": expires,
                "credited_at": credited,
            })
        atomic_write_csv(staging, "rewards.csv", fields["rewards"], rewards)

        # Bills
        bills = list(data["bill_payments"])
        next_bill_id = max_id(bills, "bill_id") + 1
        target_bill_count = len(bills) * SCALE
        categories = ["BROADBAND", "DTH", "ELECTRICITY", "FASTAG", "GAS", "MOBILE", "WATER"]
        billers = ["Tata Power", "Adani Electricity", "Airtel", "Jio", "Reliance Gas"]
        synthetic_bill_count = target_bill_count - len(bills)
        for offset in range(synthetic_bill_count):
            bill_id = next_bill_id + offset
            status_roll = offset % 10
            status = "PAID" if status_roll < 7 else "DUE" if status_roll < 9 else "OVERDUE"
            due = date(2025, 1, 1) + timedelta(days=offset % 730)
            paid = ""
            if status == "PAID":
                paid_dt = datetime(2025, 1, 1, 0, 0, 0) + timedelta(
                    days=offset % 730, hours=(offset % 24)
                )
                paid = paid_dt.strftime("%Y-%m-%d %H:%M:%S+05:30")
            bills.append({
                "bill_id": str(bill_id),
                "user_id": str((offset % TARGET_USERS) + 1),
                "biller_category": categories[offset % len(categories)],
                "biller_name": billers[offset % len(billers)],
                "consumer_number": f"{(offset % 100000000):08d}",
                "amount": f"{(100 + (offset % 500000) / 100):.2f}",
                "due_date": due.isoformat(),
                "status": status,
                "paid_at": paid,
            })
        atomic_write_csv(staging, "bill_payments.csv", fields["bill_payments"], bills)

        # Disputes
        disputes = list(data["disputes"])
        next_dispute_id = max_id(disputes, "dispute_id") + 1
        target_dispute_count = len(disputes) * SCALE
        synthetic_dispute_count = target_dispute_count - len(disputes)
        reasons = [
            "DUPLICATE_PAYMENT",
            "FRAUD",
            "MERCHANT_NOT_DELIVERED",
            "MONEY_DEBITED_NOT_CREDITED",
            "WRONG_PAYEE",
        ]
        txn_count = len(transactions)
        for offset in range(synthetic_dispute_count):
            dispute_id = next_dispute_id + offset
            raised_seconds = offset * 600
            raised = timestamp(raised_seconds)
            status_roll = offset % 10
            status = "OPEN" if status_roll < 3 else "RESOLVED" if status_roll < 8 else "REJECTED"
            resolved = ""
            if status != "OPEN":
                resolved_dt = datetime(2025, 1, 1, 0, 0, 0) + timedelta(
                    seconds=raised_seconds + 86400 * (1 + offset % 10)
                )
                resolved = resolved_dt.strftime("%Y-%m-%d %H:%M:%S+05:30")
            txn_index = (offset * 65537) % txn_count
            disputes.append({
                "dispute_id": str(dispute_id),
                "txn_id": transactions[txn_index]["txn_id"],
                "raised_by": str((offset % TARGET_USERS) + 1),
                "reason": reasons[offset % len(reasons)],
                "raised_at": raised,
                "status": status,
                "resolved_at": resolved,
            })
        atomic_write_csv(staging, "disputes.csv", fields["disputes"], disputes)

        for filename in TABLE_FILES.values():
            destination = output / filename
            if destination.exists():
                destination.unlink()
            shutil.move(str(staging / filename), str(destination))

        manifest = []
        for table, filename in TABLE_FILES.items():
            path = output / filename
            manifest.append({
                "table": table,
                "csv": filename,
                "rows": sum(1 for _ in path.open("r", encoding="utf-8")) - 1,
                "bytes": path.stat().st_size,
            })
        with (output / "manifest.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=["table", "csv", "rows", "bytes"])
            writer.writeheader()
            writer.writerows(manifest)

        print(f"Generated {output} from {seed}")
        for row in manifest:
            print(f"{row['table']}: {row['rows']} rows, {row['bytes']} bytes")
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true",
                        help="replace any existing generated large_data CSV files")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = root / "large_data"
    if output.exists() and any(output.glob("*.csv")) and not args.force:
        raise SystemExit(
            f"{output} already contains CSV files; rerun with --force to replace them"
        )
    generate(root, output)


if __name__ == "__main__":
    main()
