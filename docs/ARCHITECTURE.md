# ANHAR — Architecture & delivery plan

## Product principles
- Arabic-first RTL experience, dark navy and gold design.
- Multi-tenant SaaS: every tenant-owned record is scoped to a company; PostgreSQL RLS is mandatory.
- Branches, cost centers, roles, approval workflows, audit events and flexible fiscal periods.
- Platform subscription center is a platform-owner-only capability and is not exposed in tenant navigation or tenant APIs.

## Functional domains
1. Identity & tenancy: platform owner, companies, memberships, roles, permissions, branches.
2. Master data: products, services, categories, barcodes, units and suppliers.
3. POS: open/close shifts, sales, held invoices, returns, quotations, mixed tenders, receipt formats.
4. Procurement: purchase requests, approvals, receiving, supplier invoices and returns.
5. Inventory: movements, transfers, counts, reorder alerts and last-purchase-price valuation.
6. Accounting: four-level chart of accounts, double-entry journals, tax, currencies and fiscal periods.
7. Cash & bank: cash drawers, payment methods mapped to ledger accounts, vouchers and reconciliation.
8. Reporting: daily/monthly/yearly operational and financial reports.
9. Governance: approval engine, notifications, immutable audit log and access policies.
10. Platform subscriptions: plans, trials, strict expiry policy, grace period and add-ons; platform admin only.

## Release gates
- No fake success states or hard-coded operational totals.
- Every write operation must validate permissions and business rules server-side.
- Financial operations must post balanced journal entries atomically.
- POS sale, return and inventory movement must be covered by integration tests.
- Test tenant isolation using at least two separate companies.
- Apply migrations to a staging database and verify backup/rollback before production.

## Current implementation status
The repository currently contains a polished responsive UI foundation and navigation shell. Business modules, authentication, database schema, RLS policies, payment gateway and end-to-end workflows are not implemented yet.
