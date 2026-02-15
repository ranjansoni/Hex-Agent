# Contract Generator

Generates a contract PDF from deal JSON using a Handlebars HTML template and Puppeteer. Used by n8n after the deal is parsed and installments are calculated.

## Endpoint

- **POST /generate-contract**  
  Body (JSON): deal object with at least:
  - `client_name`, `contact_name`, `contact_email` (optional)
  - `plan_name`, `total_amount`
  - `project_term_weeks` (number or null; shown in 3 places in the template)
  - `kickoff_date` (string or null; e.g. `"2026-03-01"`)
  - `installments`: array of `{ number, amount, timing }`

  Response: PDF binary (`application/pdf`).

## Template

- **templates/contract.hbs** — Handlebars HTML. Replace this with your real contract; keep the same variable names so n8n payload still works.
- Variables: `{{client_name}}`, `{{contact_name}}`, `{{contact_email}}`, `{{plan_name}}`, `{{total_amount_formatted}}`, `{{project_term_display}}` (from `project_term_weeks`), `{{kickoff_display}}`, `{{#each installments}}` with `{{this.number}}`, `{{this.amount}}`, `{{this.timing}}`, and `{{formatNumber n}}` for numbers.
- **Important:** `project_term_weeks` is rendered in **3 places** in the placeholder (as required by the n8n instructions). Keep that when you customize the template.

## Run locally

```bash
npm install
npm start
# Default port 3200; override with PORT=3200
```

## Run with Docker

```bash
docker build -t hex-contract-generator .
docker run -p 3200:3200 hex-contract-generator
```

## Health

- **GET /health** — returns `{ "status": "ok", "service": "contract-generator" }`
