#!/usr/bin/env python3
"""Static safety audit for ENHAR BUSINESS SQL migrations.

This is a source-level check only. It does not connect to Supabase and cannot
replace integration tests against a disposable database.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
VERSION_RE = re.compile(r"^(\d+)_.*\.sql$")
CREATE_RE = re.compile(
    r"create\s+table\s+(?:if\s+not\s+exists\s+)?"
    r"(?:public\.)?([a-zA-Z_][\w]*)\s*\((.*?)\);",
    re.IGNORECASE | re.DOTALL,
)
COLUMN_RE = re.compile(r"^\s*([a-zA-Z_][\w]*)\s+", re.MULTILINE)


def main() -> int:
    if not MIGRATIONS.exists():
        print("ERROR: supabase/migrations directory not found")
        return 2

    files = sorted(MIGRATIONS.glob("*.sql"))
    errors: list[str] = []
    warnings: list[str] = []

    versions: dict[str, list[str]] = {}
    table_defs: dict[str, list[tuple[str, set[str]]]] = {}

    for path in files:
        match = VERSION_RE.match(path.name)
        if not match:
            errors.append(f"Migration filename has no numeric version prefix: {path.name}")
        else:
            versions.setdefault(match.group(1), []).append(path.name)

        sql = path.read_text(encoding="utf-8")
        for table_match in CREATE_RE.finditer(sql):
            table = table_match.group(1).lower()
            body = table_match.group(2)
            columns = {
                name.lower()
                for name in COLUMN_RE.findall(body)
                if name.lower() not in {"constraint", "primary", "unique", "foreign", "check"}
            }
            table_defs.setdefault(table, []).append((path.name, columns))

    for version, names in sorted(versions.items()):
        if len(names) > 1:
            errors.append(
                f"Duplicate migration version {version}: " + ", ".join(names)
            )

    for table, definitions in sorted(table_defs.items()):
        if len(definitions) < 2:
            continue
        reference_file, reference_cols = definitions[0]
        for filename, columns in definitions[1:]:
            if columns != reference_cols:
                only_first = sorted(reference_cols - columns)
                only_second = sorted(columns - reference_cols)
                errors.append(
                    f"Incompatible CREATE TABLE definitions for {table}: "
                    f"{reference_file} vs {filename}; "
                    f"only first={only_first}; only second={only_second}"
                )

    # High-risk financial implementation markers for human review.
    all_sql = "\n".join(p.read_text(encoding="utf-8") for p in files).lower()
    if "enhar_journal_entries" in all_sql and not re.search(
        r"create\s+(?:or\s+replace\s+)?function\s+public\.enhar_.*journal",
        all_sql,
    ):
        warnings.append(
            "Journal tables exist, but no journal-posting function was detected."
        )
    if "moyasar" in all_sql and not re.search(
        r"create\s+(?:or\s+replace\s+)?function\s+public\.enhar_.*payment",
        all_sql,
    ):
        warnings.append(
            "Payment integration exists; verify webhook authentication, idempotency and reconciliation."
        )

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
