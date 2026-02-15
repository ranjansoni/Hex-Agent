# Start n8n (Step 3)

n8n is now in your `docker-compose.yml`. Use it to build the deal-to-invoice workflows.

---

## 1. Start n8n (with the other services)

From the **AI Agent** project folder:

```bash
cd "/Users/ranjansoni/Documents/AI Projects/AI Agent"
docker compose up -d
```

This starts pdf-renderer, contract-generator, and **n8n**. The first time, it will pull the n8n image (may take a minute).

---

## 2. Open the n8n UI

In your browser go to:

**http://localhost:5678**

Log in with:

- **User:** `admin`
- **Password:** `changeme`

**Change the password** after first login: in n8n click your profile (bottom left) → Settings → change password.

---

## 3. Check n8n can reach the microservices

Inside n8n, workflows will call:

- **Proposal PDF:** `http://pdf-renderer:3100/render-pdf`
- **Contract PDF:** `http://contract-generator:3200/generate-contract`

Because n8n runs on the same Docker network (`hex-net`) as the two services, those hostnames work from inside n8n. No extra config needed.

---

## 4. Next: Build Workflow 1 (Phase 1)

Follow **EXECUTION_PLAN.md** Phase 1 (Tasks 1.1–1.4):

1. Gmail Trigger (father’s inbox, filter from son).
2. Claude Haiku node to parse the email into deal JSON.
3. Gmail node (son’s account) to search for client threads.
4. Claude again to enrich the deal from those threads.

You’ll need to add credentials in n8n for: Father’s Gmail, Son’s Gmail, and Anthropic (Claude) before the workflow can run.

---

## Optional: Run only n8n (services already up)

If the other containers are already running:

```bash
docker compose up -d n8n
```

## Stop everything

```bash
docker compose down
```

Data for n8n (workflows, credentials) is stored in the `n8n_data` volume and will still be there after `down`. To remove it too: `docker compose down -v`.
