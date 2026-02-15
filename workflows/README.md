# n8n workflow: Invoice from email (revised scope)

**Flow:** Gmail (from son, contains “invoice”) → extract client name → find or create client in billing → create invoice → reply “done”.

---

## 1. Import the workflow into n8n

1. In n8n, go to **Workflows** (left sidebar under Personal).
2. Click the **dropdown arrow** next to the red **Create workflow** button (top right).
3. Choose **Import from file** (or **Import from URL**).
4. Select the file: **`workflows/hex-invoice-from-email.json`** from this project.
5. The workflow will open in the editor with all nodes and connections.

---

## 2. Configure credentials

### Gmail (Father’s account)

- Open the **Gmail Trigger** node and the **Reply Done** node.
- For **Credential for Gmail**, create or select a Gmail OAuth2 credential using the **father’s** Gmail account (the one that receives the son’s emails).
- If the workflow uses a placeholder credential ID, replace it with your actual Gmail credential.

### Restrict trigger to “from son” (optional)

- In **Gmail Trigger**, if there is a **Filters** or **Search** field, set it so only emails from the son’s address are considered (e.g. `from:son@example.com`).
- The workflow already filters for emails whose subject or body **contains “invoice”** in the next node.

---

## 3. Configure billing API and secret

n8n must call your Hex Billing API with the shared secret.

### Option A: n8n environment variables (recommended)

If you run n8n with Docker (e.g. from this project’s `docker-compose`), add to **docker-compose.yml** under the `n8n` service:

```yaml
environment:
  # ... existing ...
  - N8N_API_SECRET=your-secret-here
  - BILLING_BASE_URL=http://host.docker.internal:3000
```

- **N8N_API_SECRET** — same value as in Hex Billing’s `.env`.
- **BILLING_BASE_URL** — base URL of Hex Billing. Use `http://host.docker.internal:3000` if the app runs on your Mac on port 3000. If Billing runs elsewhere (e.g. Tailscale), use that URL.

Restart n8n after changing:

```bash
docker compose up -d n8n
```

### Option B: Set in each HTTP node

In each **Get clients**, **Create client**, and **Create invoice** node you can hardcode or use expressions:

- **URL:** e.g. `http://host.docker.internal:3000/api/clients` (or your BILLING_BASE_URL).
- **Header:** `Authorization` = `Bearer YOUR_N8N_API_SECRET`.

Using `$env.N8N_API_SECRET` and `$env.BILLING_BASE_URL` in the nodes (as in the imported workflow) is easier if you set those env vars.

---

## 4. Hex Billing: auth and migration

- In **Hex Billing** `.env` set **N8N_API_SECRET** (same value as in n8n).
- Run migrations if you haven’t:  
  `npx prisma migrate deploy` and `npx prisma generate` in the `hex-billing` folder.
- We added n8n auth to **POST /api/clients** and **POST /api/invoices** so they accept the `Authorization: Bearer <N8N_API_SECRET>` header.

---

## 5. Test

1. **Activate** the workflow (toggle in n8n).
2. From the **son’s** Gmail, send an email to the **father’s** Gmail with “invoice” in the subject or body and a client name (e.g. “invoice client: Acme” or “invoice for Acme Corp”).
3. Within a poll interval (e.g. 1 minute), the workflow should:
   - Find or create “Acme” (or the name you used) in Hex Billing,
   - Create an invoice for that client,
   - Reply “done” to the thread.

Check **Executions** in n8n and the Hex Billing UI (Clients, Invoices) to confirm.

---

## 6. Extract client name (optional tweaks)

The **Extract client name** Code node looks for:

- “client: X” or “client - X” or “for X”
- Otherwise, the first line of the email (after stripping “Re:”, “invoice”, etc.)

You can edit that node’s code to match how the son usually writes (e.g. “Client: Acme” or “Invoice for Acme”).

---

## File

- **hex-invoice-from-email.json** — workflow definition. Re-import after editing in n8n if you want to save a new version to the repo.
