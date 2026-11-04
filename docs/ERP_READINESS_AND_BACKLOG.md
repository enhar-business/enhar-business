# ENHAR BUSINESS — ERP readiness and engineering backlog

**Scope:** repository source review only. No production database or live browser actions were performed by this report.

## Release gate

Do not advertise production readiness or accept live subscription payments until:
- SQL migration versions are unique and the complete migration chain applies cleanly to a disposable Supabase project.
- Tenant isolation tests prove that one company cannot read or mutate another company's records.
- Subscription status and quota enforcement are applied consistently to every creation path.
- Moyasar webhooks are authenticated, idempotent, amount/currency/order-bound, and reconciled.
- Sales, purchases, returns, cash sessions and journals pass end-to-end tests.
- Saudi e-invoicing requirements are implemented and tested for the actual business scenario.

## Confirmed source-level findings

1. Migration filenames contain duplicate version prefixes: 003, 005, 007 and 013. Supabase migration versions must be unique.
2. The repository contains multiple competing definitions of `enhar_staff`. One definition uses `auth_user_id/staff_code`; another uses `user_id/employee_code`. `CREATE TABLE IF NOT EXISTS` does not reconcile an existing table's columns.
3. The codebase has customer wallet schema variants and POS wallet redemption code. Their transaction type names and column layouts must be reconciled before live wallet usage.
4. POS posting creates invoices, payments, stock movements and cash movements. The reviewed implementation does not create balanced journal entries automatically.
5. Staff permission rows are persisted, but source review has not established consistent enforcement in every UI action and database RPC.
6. Subscription quota triggers exist for active memberships and cashboxes. They require concurrency, suspended-company, expired-subscription, and add-on purchase integration tests.
7. Billing UI calls the `create-subscription-payment` Edge Function. Presence of source files does not prove deployment, environment secrets, provider configuration, or successful live callbacks.
8. No automated test suite or GitHub Actions workflow was present at the repository root during this review.

## Priority engineering sequence

### P0 — Data safety and release blockers
- Consolidate duplicate migration versions into a single ordered, immutable migration history. Do not rename migrations already applied to a live database; create a documented forward-repair path instead.
- Reconcile staff, customer wallet, cashbox and stock schemas using additive migrations and explicit compatibility checks.
- Add database-level tenant-isolation tests for every tenant table and SECURITY DEFINER function.
- Ensure subscription state is checked centrally by every business write path; expired/suspended tenants must not continue posting transactions.
- Make quotas race-safe with transaction-scoped advisory locks or equivalent serialization.
- Validate webhook authenticity and make payment fulfillment idempotent. Verify amount, currency, order ID and provider invoice ID before granting access.
- Add immutable financial audit trails and prevent destructive deletion of posted financial records.

### P1 — Core ERP accounting and operations
- Double-entry posting engine with configurable chart of accounts, balanced journals, posting periods, reversals and audit history.
- Sales lifecycle: quotations, orders, POS, invoices, partial payments, credit sales, returns, refunds and credit notes.
- Purchasing lifecycle: purchase requests, purchase orders, goods receipt, supplier invoices, supplier payments and purchase returns.
- Inventory costing (weighted average/FIFO as selected), reservations, transfers, counts, reorder points, batches, serials and expiry.
- Cash/bank: multiple payment methods, cash sessions, bank reconciliation, deposits, withdrawals, petty cash and settlement differences.
- Tax engine and Saudi VAT reporting; ZATCA e-invoicing integration requires a separately tested compliance workstream.

### P2 — Saudi market differentiation
- Arabic-first RTL and English UI, multi-branch and multi-warehouse.
- Vertical workflows for salons/clinics/retail/services: appointments, staff commissions, packages, memberships, customer wallet, loyalty and CRM.
- HR: attendance, shifts, leave, payroll inputs and commission settlement.
- Procurement approvals, supplier scoring, budgets, cost centers and expense claims.
- Dashboards, saved reports, exports, scheduled reports and alerts.
- Customer self-service booking, invoice links, payment links and notifications through approved providers.
- API, webhooks, import/export, integrations and role-based access templates.

## Test plan required before production

| Area | Minimum proof |
|---|---|
| Migrations | Fresh database applies all migrations; upgrade database preserves data |
| Authentication | Signup, email confirmation, login, password reset, session expiry |
| Tenant isolation | Cross-company SELECT/INSERT/UPDATE/DELETE denied |
| Platform admin | Create, suspend, reactivate and inspect tenants; audit each action |
| Subscriptions | Trial expiry, renewal, cancellation, failed payment, duplicate webhook |
| Quotas | Exact boundary, one over limit, add-on purchase, concurrent creation |
| POS | Cash/card/bank/wallet; tax and discount math; stock and cash ledger |
| Purchases | Supplier invoice, receipt, stock cost, payment, return |
| Cashboxes | Open/close, expected vs actual, duplicate open, two-box limit |
| Accounting | Every posted source transaction generates balanced debit/credit journals |
| Security | RLS, RPC authorization, IDOR, rate limiting, secrets and audit log |
| Saudi compliance | VAT calculations, invoice QR/XML requirements and ZATCA test scenarios |

## Test integrity

The static audit is intentionally not a production database test. Passing it cannot certify accounting correctness, payment readiness, ZATCA compliance, performance, or security. Those require a disposable Supabase environment, test credentials configured by the owner, and end-to-end execution.
