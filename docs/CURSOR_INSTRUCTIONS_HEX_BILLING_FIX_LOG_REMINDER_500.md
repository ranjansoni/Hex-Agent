# Cursor instructions: Fix POST /api/invoices/[id]/log-reminder (HTTP 500)

**Use this on the computer where the Hex Billing repo is open.** The endpoint returns 500 when called with a valid invoice id and body `{ "reminderTier": "test", "daysOverdue": 0 }`. Goal: fix the error so it returns 200/201/204 and creates an `InvoiceReminderLog` row.

---

## Context

- **Route:** `POST /api/invoices/[id]/log-reminder`
- **Likely file:** `src/app/api/invoices/[id]/log-reminder/route.ts`
- **Purpose:** When n8n (or the app) sends a reminder email for an overdue invoice, it calls this to log the event.
- **Body:** `{ reminderTier?: string, daysOverdue?: number }`
- **Schema:** Model `InvoiceReminderLog` has at least: `invoiceId`, `companyId`, `reminderTier`, `daysOverdue`, `source`, `sentAt`. All of these must be set when creating a record (or match the schema’s optional/required fields).

---

## Task

1. **Open** `src/app/api/invoices/[id]/log-reminder/route.ts` (or the file that handles this path).
2. **Find the 500 cause:** Common causes:
   - **Missing `companyId`:** The handler creates `InvoiceReminderLog` but doesn’t set `companyId`. The invoice has a company (e.g. `invoice.companyId` or `invoice.client.companyId`). Load the invoice (with `companyId` or `client: { select: { companyId: true } }`) and pass that value when creating the log.
   - **Wrong or missing fields:** Prisma create fails if a required field is missing or type is wrong. Check the `InvoiceReminderLog` model in `prisma/schema.prisma` and ensure the create payload includes every required field (e.g. `invoiceId`, `companyId`, `source`, `sentAt`, and optionally `reminderTier`, `daysOverdue`).
   - **Invalid invoice id:** If the route doesn’t validate that the invoice exists (or that the user/n8n is allowed to access it), a bad id could cause a throw. Validate the invoice exists and return 404 with JSON if not.
3. **Implement or fix the handler** so that it:
   - Parses the body for `reminderTier` and `daysOverdue` (optional).
   - Loads the invoice by `[id]`, including `companyId` (e.g. `invoice.companyId` or from a relation like `client.companyId`). If invoice not found, return `NextResponse.json({ error: 'Invoice not found' }, { status: 404 })`.
   - Creates one `InvoiceReminderLog` with: `invoiceId`, `companyId` (from the invoice), `reminderTier`, `daysOverdue`, `source: 'n8n'` (or similar), `sentAt: new Date()`.
   - Returns `NextResponse.json(...)` with status 200 or 201 (or 204 with no body), **not** 500.
4. **Keep auth as-is:** The route should already use session-or-n8n auth (e.g. `requireSessionOrN8n`). Do not remove that; only fix the create logic and error handling.

---

## Acceptance criteria

- From the same machine or another with access to the app:
  ```bash
  curl -sL -w "\n%{http_code}" -X POST "https://billing-test.hex.inc/api/invoices/31/log-reminder" \
    -H "Authorization: Bearer YOUR_N8N_API_SECRET" \
    -H "Content-Type: application/json" \
    -d '{"reminderTier":"test","daysOverdue":0}'
  ```
- **Expected:** HTTP status 200 or 201 (or 204), and a new row in `InvoiceReminderLog` for that invoice with the given fields and `sentAt` set.

---

## Reference

- **Model:** `InvoiceReminderLog` in `prisma/schema.prisma` — confirm field names and required vs optional.
- **Invoice relation:** Invoice likely has `companyId` or a relation to Client which has `companyId`; use that for `InvoiceReminderLog.companyId`.
