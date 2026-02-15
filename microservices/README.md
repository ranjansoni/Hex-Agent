# Microservices (Phase 0)

Two services used by n8n for the deal-to-invoice pipeline.

| Service              | Port | Purpose |
|----------------------|------|--------|
| **pdf-renderer**     | 3100 | `POST /render-pdf` — URL → PDF (e.g. hex.inc/proposal pages) |
| **contract-generator** | 3200 | `POST /generate-contract` — deal JSON → contract PDF |

## Run both (Docker)

**First time:** Install Docker on your Mac — see [docs/INSTALL_DOCKER_MAC.md](../docs/INSTALL_DOCKER_MAC.md).

From **AI Agent** project root (use `docker compose` or `docker-compose`):

```bash
docker compose up -d
```

## Test both services

After the services are up, from **AI Agent** project root:

- **macOS/Linux:** `chmod +x scripts/test-microservices.sh && ./scripts/test-microservices.sh`
- **Windows (PowerShell):** `.\scripts\test-microservices.ps1`

This checks `/health` for both, generates a sample contract PDF, and renders example.com to PDF. Outputs are in `test-output/` (or the path you pass as the second argument to the shell script).

Manual curl examples:

- Proposal PDF: `curl -X POST http://localhost:3100/render-pdf -H "Content-Type: application/json" -d '{"url":"https://hex.inc/proposal/your-slug"}' --output proposal.pdf`
- Contract PDF: `curl -X POST http://localhost:3200/generate-contract -H "Content-Type: application/json" -d '{"client_name":"Acme","contact_name":"John","plan_name":"Growth","total_amount":35000,"project_term_weeks":12,"kickoff_date":"2026-03-01","installments":[{"number":1,"amount":20000,"timing":"Upon signing"},{"number":2,"amount":15000,"timing":"2 weeks after kickoff"}]}' --output contract.pdf`

## Run individually (local Node)

```bash
cd microservices/pdf-renderer && npm install && npm start
cd microservices/contract-generator && npm install && npm start
```

## n8n

When n8n runs in the same Docker network (e.g. uncomment the `n8n` service in `docker-compose.yml`), use:

- `http://pdf-renderer:3100/render-pdf`
- `http://contract-generator:3200/generate-contract`

If n8n runs on your host, use `http://host.docker.internal:3100` / `3200` or your machine’s IP.

## Customizing the contract

Edit **contract-generator/templates/contract.hbs**. Keep the same Handlebars variables (`client_name`, `contact_name`, `plan_name`, `total_amount_formatted`, `project_term_display`, `kickoff_display`, `installments`, `formatNumber`) so the n8n payload still works. The placeholder uses `project_term_display` in **3 places** as required by the workflow.
