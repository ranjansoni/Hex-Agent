# Cursor instructions: Add n8n auth to Hex Billing API routes

**Use this on the computer where the Hex Billing repo is open.** Goal: allow n8n (and the simulation script) to call the billing API with `Authorization: Bearer <N8N_API_SECRET>` and get JSON back instead of the HTML app.

---

## Context

- Hex Billing already has n8n auth in `src/lib/n8n-auth.ts`: `isN8nAuthenticated(req)` and `requireSessionOrN8n(req, session)`.
- Those helpers check `Authorization: Bearer <N8N_API_SECRET>` or `x-api-key: <N8N_API_SECRET>` (env: `N8N_API_SECRET`).
- Some routes already use them: e.g. `/api/invoices/unsent`, `/api/invoices/overdue`, `/api/invoices/[id]/log-reminder`, `/api/invoices/[id]/pdf`, `/api/invoices/[id]/push-and-mark`, `/api/qbo/map-client`.
- **Missing:** `GET /api/clients`, `POST /api/clients`, and `POST /api/invoices` are still session-only, so requests with only the Bearer token get the HTML app (or redirect) instead of JSON.

---

## Task

1. **Open** `src/lib/n8n-auth.ts` and confirm the exports (e.g. `requireSessionOrN8n`).
2. **Update** these route handlers to use **session OR n8n** (same pattern as the existing n8n routes):
   - **GET /api/clients** — file: `src/app/api/clients/route.ts` (likely the `GET` handler).
   - **POST /api/clients** — same file, `POST` handler.
   - **POST /api/invoices** — file: `src/app/api/invoices/route.ts`, `POST` handler.
3. **Pattern to apply:** Where the route currently uses something like `getServerSession()` and returns 401/redirect when there is no session, change it to:
   - Call `requireSessionOrN8n(req, session)` (or equivalent from `n8n-auth.ts`). If that returns “not authorized”, return a **JSON** error (e.g. `NextResponse.json({ error: 'Unauthorized' }, { status: 401 })`), **not** an HTML redirect, so n8n and the simulation script always get JSON.
4. **Reference:** Copy the auth pattern from an existing n8n-protected route, e.g. `src/app/api/invoices/unsent/route.ts` or `src/app/api/invoices/overdue/route.ts`, and reuse it in the clients and invoices routes.

---

## Acceptance criteria

- From the same machine (or a box with network access to the billing app), run:
  ```bash
  curl -sL -H "Authorization: Bearer YOUR_N8N_API_SECRET" "https://billing-test.hex.inc/api/clients"
  ```
  (Replace `YOUR_N8N_API_SECRET` with the value from Hex Billing `.env` and the URL if different.)
- **Expected:** Response body is **JSON** (e.g. array of clients or `{ data: [...] }`), not HTML.
- Same for `POST /api/clients` and `POST /api/invoices` with a valid Bearer header and JSON body: they should return JSON (201/200) or JSON error (4xx), not HTML.

---

## Files to touch (typical Next.js App Router layout)

| Route | File |
|-------|------|
| GET/POST /api/clients | `src/app/api/clients/route.ts` |
| POST /api/invoices | `src/app/api/invoices/route.ts` |

Use the same `requireSessionOrN8n` (or equivalent) pattern as in `src/app/api/invoices/unsent/route.ts` or `src/app/api/invoices/overdue/route.ts`. Ensure **all** error responses from these handlers are **JSON** (e.g. `NextResponse.json(...)`), not redirects or HTML.

---

## After the change

On the other computer (AI Agent repo), the simulation script can be run with a client name to verify end-to-end:

```bash
BILLING_BASE_URL=https://billing-test.hex.inc N8N_API_SECRET=<same-as-hex-billing-env> ./scripts/simulate-invoice-workflow.sh "Ranjan Soni"
```

If step 1 (GET /api/clients) returns JSON and the client “Ranjan Soni” is found, the script will also test POST /api/invoices and POST /api/invoices/:id/log-reminder.
