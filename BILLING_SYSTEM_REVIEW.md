# Hex Billing System — Review for n8n Integration

> **Purpose:** Compare the existing Hex Billing API (Next.js app in `../Hex Billing/hex-billing`) against the endpoints assumed in `n8n-cursor-instructions-v2.md` and identify gaps, mappings, and required changes.

---

## 1. Overview of Hex Billing

- **Stack:** Next.js (App Router), Prisma, MySQL, NextAuth.
- **Location:** `/Users/ranjansoni/Documents/AI Projects/Hex Billing/hex-billing`
- **API base:** All routes live under **`/api/`** (no `/api/v1/` prefix).
- **Auth:** Most routes use **`getServerSession(authOptions)`** and return **401 Unauthorized** if there is no session. So **browser/cookie auth only** — no API key or server-to-server auth today.
- **Tenancy:** `getCurrentCompanyId()` returns a single company (“Hex Creative Studio Inc”) — effectively single-tenant.

---

## 2. Endpoint Mapping: n8n Doc vs Hex Billing

| n8n instruction | Hex Billing reality | Match? |
|-----------------|---------------------|--------|
| `POST /api/v1/clients` | `POST /api/clients` | ✅ Path differs; body shape differs (see below). |
| `POST /api/v1/clients/{id}/map-qbo` | `POST /api/qbo/map-client` (body: `clientId`, `qboCustomerId`, `qboDisplayName`) | ✅ Same behavior, different path/body. |
| `GET /api/v1/invoices/unsent?due_date=YYYY-MM-DD` | No dedicated endpoint. Use `GET /api/invoices?invoiced=false&okayToInvoice=true&start=…&end=…` | ⚠️ Same data, different API shape. |
| `POST /api/v1/invoices/{id}/generate-pdf` | `GET /api/invoices/[id]/pdf` returns PDF (generates on the fly) | ✅ Use GET for “generate + download”. |
| `POST /api/v1/invoices/{id}/mark-sent` | `POST /api/invoices/[id]/push-and-mark` (pushes to QBO + sets `invoiced=true`, `invoiceNumber`, etc.) | ✅ “Mark sent” in Hex = push to QBO + mark invoiced. |
| `GET /api/v1/invoices/overdue` | No dedicated endpoint. Use `GET /api/invoices?invoiced=true&paymentStatus=UNPAID` + filter by `plannedInvoiceDate < today` | ⚠️ Need to filter in n8n or add endpoint. |
| `POST /api/v1/invoices/{id}/log-reminder` | No equivalent. `InvoiceSendLog` exists but requires `sentById` (User) and is created only when sending via `/api/invoices/[id]/send` | ❌ Missing for n8n-driven reminders. |

---

## 3. Detailed Findings

### 3.1 Create client — `POST /api/clients`

**Hex schema (from `src/app/api/clients/route.ts`):**

- **Required:** `name`, `dateSigned`, `totalDealSize`, `kickoffDate`, `proposedEndDate`, `numInstallments`
- **Optional:** `companyName`, `source`, `billingTerms`, `autoGenerate`, `plans` (array of `{ stage, amount, plannedInvoiceDate }`)

**Not accepted on create:** `billingEmail`, `billingContactName`, `billingEmailCc`. These exist on the Client model and can be updated via **`PUT /api/clients/[id]`** (allowed keys include `billingEmail`, `billingContactName`, etc.).

**n8n workflow has:** `client_name`, `contact_name`, `contact_email`, `plan_name`, `total_amount`, `installments`, `project_term_weeks`, `kickoff_date`.

**Mapping for n8n:**

- `client_name` → `name` (or `companyName` depending on how you treat “client”)
- `contact_name` → set after create via PUT: `billingContactName`
- `contact_email` → set after create via PUT: `billingEmail`
- `total_amount` → `totalDealSize`
- `kickoff_date` → `kickoffDate`
- `proposedEndDate`: derive from kickoff + `project_term_weeks` (e.g. kickoff + N weeks)
- `numInstallments` → length of installments array
- `dateSigned` → e.g. today or from deal
- `plans` → build from installments: each `{ stage: "Installment N", amount, plannedInvoiceDate }` (you have timing like “Upon signing”, “2 weeks after kickoff” — need to compute dates from kickoff)

So: **one POST then one PUT** (to set billing contact + email) is enough, or you can extend POST to accept optional `billingEmail` / `billingContactName` and do it in one call.

---

### 3.2 Map client to QBO — `POST /api/qbo/map-client`

**Hex:** `POST /api/qbo/map-client`  
Body: `{ qboCustomerId, qboDisplayName, clientId }` (optional: `qboSyncToken`).

**n8n doc:** `POST /api/v1/clients/{id}/map-qbo` with body `{ "qbo_customer_id": "…" }`.

**Mapping:** n8n calls `POST /api/qbo/map-client` with:

- `clientId` = billing system client id (from create response)
- `qboCustomerId` = QBO customer id (from Workflow 2)
- `qboDisplayName` = client name / company name for display

No Hex changes required; only n8n request shape.

---

### 3.3 Unsent invoices (due on a given date)

**n8n:** `GET /api/v1/invoices/unsent?due_date=YYYY-MM-DD`

**Hex:** No `unsent` or `due_date` query. Use:

- `GET /api/invoices?invoiced=false&okayToInvoice=true&start=YYYY-MM-DD&end=YYYY-MM-DD`

That returns invoices that are approved to invoice (`okayToInvoice=true`), not yet invoiced (`invoiced=false`), with `plannedInvoiceDate` in the date range. So “due_date” = use the same date for `start` and `end` for “due today”.

Optional improvement: add a convenience route, e.g. `GET /api/invoices/unsent?due_date=YYYY-MM-DD`, that does this query and returns the same structure.

---

### 3.4 Generate invoice PDF

**n8n:** `POST /api/v1/invoices/{id}/generate-pdf`  
**Hex:** `GET /api/invoices/[id]/pdf` — returns PDF binary (generates on demand). No POST needed.

n8n can use **GET** with the invoice id; no Hex change.

---

### 3.5 Mark invoice as sent

**n8n:** `POST /api/v1/invoices/{id}/mark-sent`  
**Hex:** “Sent” = created in QBO and marked in Hex. The relevant endpoint is **`POST /api/invoices/[id]/push-and-mark`**.

- Pushes invoice to QBO (creates QBO invoice, gets `DocNumber`).
- Updates Hex: `invoiced=true`, `invoiceNumber`, `actualInvoiceDate`, `paymentStatus=UNPAID`, `qboInvoiceId`, etc.

Body: `{ actualInvoiceDate, serviceItemId? }`. So n8n should call this with the chosen invoice date (e.g. today) and optionally `serviceItemId` if you have a preferred QBO service item.

No separate “mark-sent without QBO” in Hex; design is “sent = in QBO”. So n8n’s “mark-sent” step = **push-and-mark**.

---

### 3.6 Overdue invoices

**n8n:** `GET /api/v1/invoices/overdue`  
**Hex:** No dedicated `overdue` route. You can:

- `GET /api/invoices?invoiced=true&paymentStatus=UNPAID` and then in n8n filter items where `plannedInvoiceDate` (or due date) &lt; today.

Alternatively add **`GET /api/invoices/overdue`** that returns unpaid invoices with due date &lt; today (and optionally apply company/late-fee logic). That would simplify n8n and centralize “overdue” definition.

---

### 3.7 Log reminder

**n8n:** `POST /api/v1/invoices/{id}/log-reminder` (after n8n sends a reminder email via Gmail).

**Hex:** No such endpoint. Sending is done via `POST /api/invoices/[id]/send`, which creates an `InvoiceSendLog` with:

- `sentById` (required — User id)
- subject, body, tracking, etc.

So reminders sent **by n8n** (Gmail) are not logged in Hex today.

**Options:**

1. **New endpoint:** e.g. `POST /api/invoices/[id]/log-reminder` that creates a minimal `InvoiceSendLog` (or a separate `InvoiceReminderLog` if you prefer) with:
   - `sentById` nullable or a fixed “system” user id
   - Optional: reminder tier, days overdue, template name
2. **Schema:** If you keep using `InvoiceSendLog`, you’d need to allow `sentById` to be null or add a “system” user and use it for n8n reminders.

Recommendation: add **`POST /api/invoices/[id]/log-reminder`** and either allow `sentById` to be null for this case or introduce a system user used only for automation.

---

## 4. Authentication Blocker for n8n

All of the above routes (clients, invoices, qbo/map-client, etc.) use **`getServerSession(authOptions)`** and return **401** when there is no session. n8n runs server-to-server and has no browser cookies, so **every call would get 401** unless something changes.

**Ways to fix:**

1. **Dedicated n8n auth**
   - New env var, e.g. `N8N_API_SECRET`.
   - New middleware or wrapper used only for “n8n” routes (e.g. under `/api/n8n/` or same paths with a header).
   - If `Authorization: Bearer <N8N_API_SECRET>` (or `x-api-key: <N8N_API_SECRET>`) is valid, skip session and set `companyId` from `getCurrentCompanyId()` (or from a claim) and run the same logic as the existing handlers. No user id for audit is fine for “system” actions; you can log “n8n” or “system” in activity logs.
2. **Reuse cron pattern**
   - Hex already uses `CRON_SECRET` (e.g. `x-cron-secret` or `Bearer` with `EMAIL_CRON_SECRET`) for cron endpoints. You could use the same secret for “n8n” and allow the same routes to be called with that secret instead of a session (e.g. if `x-cron-secret === CRON_SECRET` or `Authorization: Bearer CRON_SECRET`, treat as server-to-server and bypass session).
3. **Separate “n8n” routes**
   - Duplicate the needed operations under e.g. `/api/n8n/clients`, `/api/n8n/invoices/...`, etc., and protect only those with the shared secret. Internally they call the same Prisma/service logic.

Recommendation: one of (1) or (3) with a dedicated `N8N_API_SECRET` so you can rotate it independently of cron. Option (2) is quick but ties n8n to cron secret.

---

## 5. Summary: What Exists vs What’s Needed

| Item | Status | Action |
|------|--------|--------|
| Create client | Exists | Map n8n fields; optionally extend POST with `billingEmail`/`billingContactName` or use POST + PUT. |
| Map client to QBO | Exists | n8n calls `POST /api/qbo/map-client` with correct body. |
| List unsent invoices (by date) | Exists via query params | Use `GET /api/invoices?invoiced=false&okayToInvoice=true&start=&end=`. Optional: add `GET /api/invoices/unsent?due_date=`. |
| Invoice PDF | Exists | Use `GET /api/invoices/[id]/pdf`. |
| Mark sent (push to QBO + mark) | Exists | Use `POST /api/invoices/[id]/push-and-mark`. |
| List overdue invoices | Partial | Use GET + filter, or add `GET /api/invoices/overdue`. |
| Log reminder | Missing | Add `POST /api/invoices/[id]/log-reminder` (+ optional schema/migration for `sentById` or system user). |
| Auth for server-to-server | Missing | Add N8N_API_SECRET (or reuse cron secret) and allow authenticated server-to-server calls for the above operations. |

---

## 6. Recommended Next Steps (for Hex Billing repo)

1. **Auth**
   - Add `N8N_API_SECRET` (or document use of existing cron secret).
   - Implement middleware or route-level check: if request has valid secret, treat as n8n and skip session; set company (and optionally “system” user) and continue.
2. **Client create (optional)**
   - Extend `POST /api/clients` to accept optional `billingEmail`, `billingContactName`, `billingEmailCc` so n8n can create + set billing in one call.
3. **Overdue (optional)**
   - Add `GET /api/invoices/overdue` returning unpaid invoices with due date &lt; today (and any company filters you already use).
4. **Unsent (optional)**
   - Add `GET /api/invoices/unsent?due_date=YYYY-MM-DD` that delegates to the same query as above for clarity.
5. **Log reminder**
   - Add `POST /api/invoices/[id]/log-reminder` (body e.g. `{ reminderTier?, daysOverdue? }`) and create an `InvoiceSendLog` (or dedicated reminder log) with `sentById` null or system user.

Once these are in place, the n8n execution plan can use the exact Hex paths and request bodies described in this document and in the updated EXECUTION_PLAN (billing section).
