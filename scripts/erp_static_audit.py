#!/usr/bin/env python3
"""Static source audit for ENHAR BUSINESS SQL migrations.

This checks migration naming and known compatibility repairs. It is deliberately
not a substitute for applying migrations to a disposable Supabase database.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
VERSION_RE = re.compile(r"^(\d+)_.*\.sql$")


def main() -> int:
    if not MIGRATIONS.exists():
        print("ERROR: supabase/migrations directory not found")
        return 2

    files = sorted(MIGRATIONS.glob("*.sql"))
    errors: list[str] = []
    warnings: list[str] = []
    versions: dict[str, list[str]] = {}

    for path in files:
        match = VERSION_RE.match(path.name)
        if not match:
            errors.append(f"Migration filename has no numeric version prefix: {path.name}")
        else:
            versions.setdefault(match.group(1), []).append(path.name)

    for version, names in sorted(versions.items()):
        if len(names) > 1:
            errors.append(f"Duplicate migration version {version}: " + ", ".join(names))

    # Repeated CREATE TABLE IF NOT EXISTS statements are intentional historical
    # compatibility attempts, not schema reconciliation. Require a forward
    # migration to explicitly add the columns needed by the alternate layouts.
    repair_files = [p for p in files if "schema_reconciliation" in p.name]
    if not repair_files:
        errors.append("Missing additive schema reconciliation migration.")
    else:
        repair_sql = "\n".join(p.read_text(encoding="utf-8").lower() for p in repair_files)
        required_repairs = {
            "enhar_staff": {"employee_code", "staff_code", "can_perform_services", "show_in_pos"},
            "enhar_appointments": {"staff_id", "service_staff_id", "appointment_number"},
            "enhar_customer_wallet_transactions": {"wallet_id", "balance_after", "payment_method"},
            "enhar_stock_count_lines": {"count_id", "stock_count_id", "difference_quantity"},
            "enhar_cash_movements": {"reference"},
            "enhar_cash_sessions": {"cashbox_id", "register_id", "actual_amount", "counted_amount"},
            "enhar_invoice_settings": {"show_logo", "show_customer_details", "show_qr_code"},
        }
        for table, columns in required_repairs.items():
            marker = f"alter table public.{table}"
            if marker not in repair_sql:
                errors.append(f"Reconciliation migration does not alter {table}.")
                continue
            for column in sorted(columns):
                if not re.search(rf"add column if not exists\s+{re.escape(column)}\b", repair_sql):
                    errors.append(f"Reconciliation migration missing {table}.{column}.")

    # Financial safety marker: do not silently claim automated journal posting.
    all_sql = "\n".join(p.read_text(encoding="utf-8") for p in files).lower()
    if "enhar_journal_entries" in all_sql and not re.search(
        r"create\s+(?:or\s+replace\s+)?function\s+public\.enhar_.*journal",
        all_sql,
    ):
        warnings.append("Journal tables exist, but no journal-posting function was detected.")

    print(f"Scanned {len(files)} SQL migration files.")
    for warning in warnings:
        print(f"WARN: {warning}")
    for error in errors:
        print(f"BLOCKER: {error}")

    if errors:
        print(f"\nStatic audit FAILED: {len(errors)} blocker(s), {len(warnings)} warning(s).")
        return 1
    print(f"\nStatic audit PASSED: {len(warnings)} warning(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
