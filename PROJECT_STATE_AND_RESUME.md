# Hex Studio n8n Pipeline — Project State & Resume Guide

**Last updated:** 2026-02-13  
**GitHub:** https://github.com/ranjansoni/Hex-Agent  
**Purpose:** Single reference for everything done so far. Use this to resume work or recover context (e.g. after a laptop crash or switching to Hex Billing work).

---

## 1. What This Project Is

- **Goal:** Automate Hex Studio’s deal-to-invoice flow using **n8n** and the **Hex Billing** app.
- **Flow:** Son emails father → contract + proposal PDFs → e-sign (Dropbox Sign) → onboarding in QuickBooks + Hex Billing → daily invoices and reminders.
- **Sources of truth:**
  - **n8n instructions:** `n8n-cursor-instructions-v2.md` (full step-by-step for 3 workflows).
  - **Execution plan:** `EXECUTION_PLAN.md` (phases, tasks, acceptance criteria for implementation).

---

## 2. Where Things Live

| Item | Location |
|------|----------|
| **n8n instructions** | `AI Agent/n8n-cursor-instructions-v2.md` |
| **Execution plan (phases 0–7)** | `AI Agent/EXECUTION_PLAN.md` |
| **Billing system review** | `AI Agent/BILLING_SYSTEM_REVIEW.md` (original); `Hex Billing/hex-billing/docs/BILLING_SYSTEM_REVIEW.md` (copy in repo) |
| **Billing n8n setup** | `Hex Billing/hex-billing/N8N_SETUP.md` |
| **This resume doc** | `AI Agent/PROJECT_STATE_AND_RESUME.md` |
| **Microservices** | `AI Agent/microservices/` (pdf-renderer, contract-generator) |
| **Docker Compose** | `AI Agent/docker-compose.yml` |

**Two codebases:**

- **AI Agent** — Docs + microservices (PDF renderer, contract generator). No billing code here.
- **Hex Billing** — Next.js app at `Hex Billing/hex-billing/`. Billing API + n8n integration live here.

---

## 3. What’s Been Done

### 3.1 Planning & docs (AI Agent)

- **EXECUTION_PLAN.md** — 7 phases, 22+ tasks: Phase 0 (microservices), Phase 1–5 (workflows), Phase 6 (testing), Phase 7 (docs). Written so a lower-cost model can execute tasks from the plan.
- **BILLING_SYSTEM_REVIEW.md** — Comparison of n8n-assumed API vs Hex Billing; gap analysis; recommended changes (all of which have been implemented).

### 3.2 Billing system changes (Hex Billing repo)

All in: **`/Users/ranjansoni/Documents/AI Projects/Hex Billing/hex-billing/`**

| Change | Details |
|--------|--------|
| **n8n auth** | `src/lib/n8n-auth.ts`: `isN8nAuthenticated(req)` and `requireSessionOrN8n(req, session)`. Checks `Authorization: Bearer <secret>` or `x-api-key: <secret>`. |
| **Env var** | `N8N_API_SECRET` — set in Hex Billing `.env`; n8n sends this header when calling the billing API. |
| **POST /api/clients** | Extended to accept optional `billingEmail`, `billingContactName`, `billingEmailCc` on create. |
| **GET /api/invoices/unsent** | New. Query: `?due_date=YYYY-MM-DD`. Returns invoices due that day, not yet sent. Auth: session or n8n secret. |
| **GET /api/invoices/overdue** | New. Returns sent, unpaid, past-due invoices; each has `daysOverdue`. Auth: session or n8n secret. |
| **POST /api/invoices/[id]/log-reminder** | New. Body: `{ reminderTier?, daysOverdue? }`. Writes to `InvoiceReminderLog`. Auth: session or n8n secret. |
| **Auth bypass** | These routes accept **either** session **or** valid `N8N_API_SECRET`: pdf, push-and-mark, qbo/map-client, unsent, overdue, log-reminder. |
| **Schema** | New model `InvoiceReminderLog` (invoiceId, companyId, reminderTier, daysOverdue, source, sentAt). |
| **Migration** | `prisma/migrations/20260212000000_add_invoice_reminder_log/migration.sql` |

**To finish billing setup (when you’re back):**

1. In Hex Billing `.env`: set `N8N_API_SECRET=<strong random value>`.
2. Run: `npx prisma migrate deploy` and `npx prisma generate` in `hex-billing/`.

**Docs in Hex Billing:** `N8N_SETUP.md` (root), `docs/BILLING_SYSTEM_REVIEW.md`.

### 3.3 Microservices (AI Agent)

**Path:** `AI Agent/microservices/`

| Service | Port | Purpose |
|---------|------|--------|
| **pdf-renderer** | 3100 | `POST /render-pdf` — body `{ "url": "https://..." }` → PDF (e.g. hex.inc/proposal pages). |
| **contract-generator** | 3200 | `POST /generate-contract` — deal JSON → contract PDF (Handlebars + Puppeteer). |

- **pdf-renderer:** `package.json`, `server.js`, `Dockerfile`, `README.md`. Working; 30s timeout; health at `/health`.
- **contract-generator:** `package.json`, `server.js`, `templates/contract.hbs`, `Dockerfile`, `README.md`. Placeholder contract with all merge fields; `project_term_weeks` in 3 places; `formatNumber` helper. Replace `contract.hbs` with real contract when ready.
- **docker-compose.yml** (AI Agent root): runs pdf-renderer, contract-generator, **and n8n** (port 5678). n8n env placeholders for `N8N_API_SECRET` and `BILLING_BASE_URL` are in comments.
- **Revised-scope workflow:** `workflows/hex-invoice-from-email.json` — Gmail (from son, contains “invoice”) → extract client → find/create client in billing → create invoice → reply “done”. **Imported in n8n** as “Hex - Invoice from email (revised scope)”.

**To run (when you’re back):** From `AI Agent`: `docker compose up -d`. Test with `./scripts/test-microservices.sh`.

---

## 4. Revised-scope workflow (current focus)

- **Workflow:** “Hex - Invoice from email (revised scope)” — imported in n8n from `workflows/hex-invoice-from-email.json`.
- **Flow:** Gmail Trigger (from son, subject/body contains “invoice”) → filter → Extract client name → Get clients (billing) → Find client by partial name → If no match: Create client (billing) → Merge → Ensure clientId → Create invoice (billing) → Reply “done”.
- **Status:** Workflow imported; **to finish:** set Gmail credentials (father’s) on Gmail Trigger and Reply Done; set n8n env vars (see below); then test.

**Env vars for n8n (in docker-compose or n8n settings):**

- **N8N_API_SECRET** — Generate once (e.g. `openssl rand -hex 32`). Put the **same** value in:
  - Hex Billing `.env`: `N8N_API_SECRET=...`
  - AI Agent `docker-compose.yml` under n8n: `- N8N_API_SECRET=...`
- **BILLING_BASE_URL** — When Hex Billing runs on your Mac at localhost:3000 and n8n runs in Docker, use: `http://host.docker.internal:3000`

**When you come back:** Open n8n (http://localhost:5678), fix any credential warnings on Gmail Trigger and Reply Done, ensure N8N_API_SECRET and BILLING_BASE_URL are set and Hex Billing is running, then run “Execute workflow from Gmail Trigger1” or send a test email (from son to father, containing “invoice” and a client name).

---

## 5. What’s Not Done Yet

- **Full Workflow 1** (original plan) — Claude parse, proposal/contract PDFs, Dropbox Sign, etc. Deferred; revised scope is “invoice from email” only for now.
- **Real contract template** — Still the placeholder; replace `microservices/contract-generator/templates/contract.hbs` when needed.
- **Dropbox Sign** — Not in revised scope yet.
- **End-to-end tests** — Not run.

---

## 6. How to Resume

1. **Read this file** and `EXECUTION_PLAN.md` (at least Phase 0 and Phase 1).
2. **Billing:** Ensure Hex Billing has `N8N_API_SECRET` in `.env` and migrations are applied (`npx prisma migrate deploy` in `hex-billing/`).
3. **Microservices:** From `AI Agent`, run `docker-compose up -d` and hit `/health` on 3100 and 3200 (or test PDF endpoints).
4. **Next implementation step:** Phase 1 in EXECUTION_PLAN — build Workflow 1 in n8n (Gmail trigger → Claude parse → son’s Gmail search → Claude enrich). Use the plan’s task list (e.g. Task 1.1–1.4) and the API/field mappings in BILLING_SYSTEM_REVIEW / N8N_SETUP.
5. **If context is lost:** Re-read `n8n-cursor-instructions-v2.md` for business rules and step order; use EXECUTION_PLAN for technical tasks and BILLING_SYSTEM_REVIEW + N8N_SETUP for billing API details.

---

## 7. Key Env / Config (for n8n)

- **Hex Billing base URL** — Your Hex Billing app URL (e.g. over Tailscale). All billing endpoints are under `/api/` (see N8N_SETUP.md).
- **N8N_API_SECRET** — Same value in Hex Billing `.env` and in n8n (sent as Bearer or x-api-key when calling Hex Billing).
- **Microservices** — When n8n runs in same Docker network: `http://pdf-renderer:3100/render-pdf`, `http://contract-generator:3200/generate-contract`. From host: `http://localhost:3100` / `http://localhost:3200`.

---

## 8. File Checklist (don’t lose these)

**AI Agent:**

- `n8n-cursor-instructions-v2.md`
- `EXECUTION_PLAN.md`
- `BILLING_SYSTEM_REVIEW.md`
- `PROJECT_STATE_AND_RESUME.md` (this file)
- `docker-compose.yml`
- `microservices/README.md`
- `microservices/pdf-renderer/` (package.json, server.js, Dockerfile, README.md)
- `microservices/contract-generator/` (package.json, server.js, templates/contract.hbs, Dockerfile, README.md)

**Hex Billing (hex-billing/):**

- `N8N_SETUP.md`
- `docs/BILLING_SYSTEM_REVIEW.md`
- `src/lib/n8n-auth.ts`
- `src/app/api/clients/route.ts` (billing fields on create)
- `src/app/api/invoices/unsent/route.ts`
- `src/app/api/invoices/overdue/route.ts`
- `src/app/api/invoices/[id]/log-reminder/route.ts`
- `src/app/api/invoices/[id]/pdf/route.ts` (n8n auth added)
- `src/app/api/invoices/[id]/push-and-mark/route.ts` (n8n auth added)
- `src/app/api/qbo/map-client/route.ts` (n8n auth added)
- `prisma/schema.prisma` (InvoiceReminderLog + relation on Invoice)
- `prisma/migrations/20260212000000_add_invoice_reminder_log/migration.sql`

---

*You can resume by opening this file and EXECUTION_PLAN.md, then continuing from Phase 1 or from testing the microservices.*
