# n8n Workflow Automation — Execution Plan
# Hex Studio: Deal-to-Invoice Pipeline

> **Source:** `n8n-cursor-instructions-v2.md`
> **Created:** 2026-02-12
> **Status:** Planning

---

## Overview

Build 3 n8n workflows + 2 supporting microservices to automate Hex Studio's deal-to-invoice pipeline.

| Component | Description |
|---|---|
| **Workflow 1** | Deal Intake → Contract Sent for E-Signing (11 steps) |
| **Workflow 2** | Signature Complete → Client Onboarding (8 steps) |
| **Workflow 3** | Daily Invoice & Reminder Runner (6 steps) |
| **Microservice A** | HTML-to-PDF renderer (Puppeteer) for proposals + contracts |
| **Microservice B** | Contract template engine (Handlebars → PDF) |

---

## Pre-Requisites (Verify Before Starting)

Before any implementation, the following must be confirmed:

- [ ] **n8n instance** is running (self-hosted, Docker, latest stable)
- [ ] **Father's Gmail** OAuth2 credentials available
- [ ] **Son's Gmail** OAuth2 credentials available (father has delegated access)
- [ ] **Anthropic API key** (for Claude Haiku)
- [ ] **Dropbox Sign / HelloSign API key** obtained
- [ ] **QuickBooks Online** OAuth2 app created (client ID, client secret, realm ID)
- [ ] **Notion API key** + Contracts database ID (if using Notion for anything)
- [ ] **Billing System** REST API is live and accessible via Tailscale
  - Verify all 7 endpoints exist: `POST /clients`, `POST /clients/{id}/map-qbo`, `GET /invoices/unsent`, `POST /invoices/{id}/generate-pdf`, `POST /invoices/{id}/mark-sent`, `GET /invoices/overdue`, `POST /invoices/{id}/log-reminder`
- [ ] **hex.inc/proposal/{slug}** pages are live and accessible
- [ ] **Docker environment** can run additional containers alongside n8n (for microservices)
- [ ] Contract template document is available (current Notion template or Word/HTML version)

---

## Phase 0: Infrastructure & Microservices

> These must be built first because Workflows 1 and 2 depend on them.

### Task 0.1: Build HTML-to-PDF Microservice (Puppeteer)

**Purpose:** Convert web pages (hex.inc/proposal URLs) to PDF files.

**What to build:**
- A lightweight Node.js + Express microservice
- Single endpoint: `POST /render-pdf`
- Request body: `{ "url": "https://hex.inc/proposal/acme-corp" }`
- Response: PDF binary (application/pdf)
- Uses Puppeteer in headless mode to navigate to the URL, wait for full render, then export as PDF
- Dockerized, runs alongside n8n

**Acceptance criteria:**
1. `POST /render-pdf` with a valid URL returns a well-formatted PDF
2. Handles timeouts gracefully (30s max render time)
3. Returns proper error codes (400 for bad URL, 504 for timeout)
4. Docker container starts cleanly and stays healthy
5. PDF is letter-size, includes all CSS/images from the page

**File structure:**
```
microservices/
  pdf-renderer/
    Dockerfile
    package.json
    server.js        # Express server with /render-pdf endpoint
    README.md
```

**Key implementation details:**
```javascript
// server.js - core logic
const puppeteer = require('puppeteer');
const express = require('express');
const app = express();
app.use(express.json());

app.post('/render-pdf', async (req, res) => {
  const { url } = req.body;
  if (!url) return res.status(400).json({ error: 'url is required' });

  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'networkidle0', timeout: 30000 });
  const pdf = await page.pdf({ format: 'Letter', printBackground: true });
  await browser.close();

  res.set('Content-Type', 'application/pdf');
  res.send(pdf);
});

app.listen(3100, () => console.log('PDF renderer on :3100'));
```

---

### Task 0.2: Build Contract Template Engine (Handlebars → PDF)

**Purpose:** Generate contract PDFs from a Handlebars HTML template with deal variables.

**What to build:**
- A Node.js + Express microservice
- Single endpoint: `POST /generate-contract`
- Request body: deal JSON (client_name, contact_name, plan_name, total_amount, installments array, project_term_weeks, kickoff_date)
- Response: PDF binary
- Uses Handlebars to render an HTML template, then Puppeteer to convert to PDF
- The HTML template must match the existing contract format

**Acceptance criteria:**
1. All deal variables are correctly interpolated
2. `project_term_weeks` is replaced in **all 3 locations** in the contract body
3. Installment table renders correctly for 1, 2, and 3 installment scenarios
4. PDF looks professional (proper fonts, spacing, layout)
5. Dockerized alongside the PDF renderer (can share the same container or be separate)

**File structure:**
```
microservices/
  contract-generator/
    Dockerfile
    package.json
    server.js
    templates/
      contract.hbs    # Handlebars HTML template
      styles.css      # Contract styling
    README.md
```

**Key implementation details:**
- The contract template needs to be created from the existing Notion contract
- Template variables: `{{client_name}}`, `{{contact_name}}`, `{{plan_name}}`, `{{total_amount}}`, `{{installments}}` (array), `{{project_term_weeks}}`, `{{kickoff_date}}`
- The `{{project_term_weeks}}` placeholder appears 3 times in the body — the template handles this naturally via Handlebars

**Request body schema:**
```json
{
  "client_name": "Acme Corp",
  "contact_name": "John Smith",
  "contact_email": "john@acme.com",
  "plan_name": "Growth",
  "total_amount": 35000,
  "project_term_weeks": 12,
  "kickoff_date": "2026-03-01",
  "installments": [
    { "number": 1, "amount": 20000, "timing": "Upon signing" },
    { "number": 2, "amount": 15000, "timing": "2 weeks after kickoff" }
  ]
}
```

---

### Task 0.3: Docker Compose Setup

**Purpose:** Orchestrate n8n + microservices in a single docker-compose setup.

**What to build:**
- `docker-compose.yml` at project root
- Services: n8n, pdf-renderer, contract-generator
- Shared Docker network so n8n can call microservices by hostname
- Volume mounts for n8n data persistence
- Environment variable configuration

**Acceptance criteria:**
1. `docker-compose up` starts all 3 services
2. n8n can reach `http://pdf-renderer:3100/render-pdf`
3. n8n can reach `http://contract-generator:3200/generate-contract`
4. n8n data persists across restarts
5. Health checks for all services

---

## Phase 1: Workflow 1 — Steps 1-4 (Email Trigger + AI Parsing)

> Deal intake: receive email, parse with AI, search for more context.

### Task 1.1: Gmail Trigger Node (Father's Inbox)

**What to build in n8n:**
- Gmail Trigger node (poll mode recommended for reliability)
- Filter: only emails from son's address (`{{SON_GMAIL}}`)
- Alternative: label-based trigger if a Gmail filter auto-labels incoming deal emails
- Output fields: `subject`, `body`, `from`, `messageId`, `threadId`

**n8n node configuration:**
- Node type: `Gmail Trigger`
- Credential: Father's Gmail OAuth2
- Poll interval: every 1 minute (or use webhook if supported)
- Filter: `from:{{SON_GMAIL}}`

**Acceptance criteria:**
1. Node triggers when son sends email to father
2. Does NOT trigger for other emails
3. Email subject and full body text are available in output

---

### Task 1.2: Claude Haiku Email Parser

**What to build in n8n:**
- HTTP Request node calling Anthropic Claude API
- System prompt from the instructions (extracts client_name, contact_name, contact_email, plan_name, proposal_url, client_slug, kickoff_date, notes)
- Model: `claude-haiku-4-5-20251001`
- Parse JSON response

**n8n node configuration:**
- Node type: `HTTP Request`
- Method: POST
- URL: `https://api.anthropic.com/v1/messages`
- Headers:
  - `x-api-key`: `{{ANTHROPIC_API_KEY}}`
  - `anthropic-version`: `2023-06-01`
  - `content-type`: `application/json`
- Body (JSON):
```json
{
  "model": "claude-haiku-4-5-20251001",
  "max_tokens": 500,
  "system": "<system prompt from instructions>",
  "messages": [
    { "role": "user", "content": "Subject: {{$node['Gmail Trigger'].json.subject}}\n\nBody: {{$node['Gmail Trigger'].json.body}}" }
  ]
}
```
- Follow with a `Code` node to parse the JSON string from Claude's response

**Acceptance criteria:**
1. Correctly parses a well-structured deal email (all fields populated)
2. Correctly handles a vague email (nulls for missing fields)
3. Output is valid JSON with all expected fields
4. `client_slug` is generated when no proposal URL exists

**Test emails to validate:**
- Full info: "Hey Dad, closed Acme Corp. John Smith, john@acme.com. Growth plan. https://hex.inc/proposal/acme-corp"
- Minimal: "Hey, new deal with Smith Industries. Can you send the contract?"
- Partial: "Got Johnson & Co signed up — they want the Enterprise plan. Start date March 15."

---

### Task 1.3: Son's Gmail Search for Client Context

**What to build in n8n:**
- Gmail node (NOT trigger — action node) using son's Gmail credentials
- Search for emails matching client name, contact name, or contact email
- Return up to 10 most recent messages

**n8n node configuration:**
- Node type: `Gmail`
- Credential: Son's Gmail OAuth2
- Operation: `Get Many`
- Search query: `{{client_name}} OR {{contact_email}} OR {{contact_name}}`
- Limit: 10
- Return: full message content (not just headers)

**Acceptance criteria:**
1. Searches son's inbox successfully
2. Returns relevant client correspondence
3. Handles case where no results found (empty array)

---

### Task 1.4: Claude Haiku Thread Enrichment

**What to build in n8n:**
- HTTP Request node calling Claude API (second time)
- System prompt: reads the email threads and fills in null fields from Task 1.2
- Also extracts `total_amount` and `project_term_weeks`
- Merges with existing deal data (non-null fields stay)

**n8n node configuration:**
- Same Claude API setup as Task 1.2 but with the enrichment system prompt
- Input: deal JSON from Task 1.2 + concatenated email thread content from Task 1.3
- A `Code` node to merge: take the enriched output and merge with original, preferring non-null values from original

**Acceptance criteria:**
1. Fills in previously null fields when evidence exists in threads
2. Does NOT overwrite existing non-null values
3. Extracts `total_amount` and `project_term_weeks` when mentioned
4. Returns complete deal JSON

---

## Phase 2: Workflow 1 — Steps 5-7 (Validation + PDF + Installments)

### Task 2.1: Missing Fields Check + Reply to Son

**What to build in n8n:**
- IF node: checks if `plan_name == null OR contact_email == null`
- True branch: Gmail reply to son asking for missing info, then STOP
- False branch: continue to next step

**n8n node configuration:**
- Node type: `IF`
- Condition: `{{ $json.plan_name === null || $json.contact_email === null }}`
- True → Gmail node (father's account, Reply action)
  - Reply to: original trigger email `messageId`
  - Body: dynamically list which fields are missing
- True → `Stop and Error` node (ends execution)
- False → continue

**Acceptance criteria:**
1. Workflow stops and replies when critical fields are missing
2. Reply email clearly lists which fields are needed
3. Workflow continues when all critical fields are present

---

### Task 2.2: Proposal PDF Generation

**What to build in n8n:**
- HTTP Request node calling the PDF renderer microservice (from Task 0.1)
- Input: proposal URL from deal data
- Output: PDF binary data

**n8n node configuration:**
- Node type: `HTTP Request`
- Method: POST
- URL: `http://pdf-renderer:3100/render-pdf`
- Body: `{ "url": "https://hex.inc/proposal/{{client_slug}}" }`
- Response format: File/Binary

**Acceptance criteria:**
1. Successfully generates PDF from a live hex.inc/proposal page
2. PDF includes all visual elements (images, CSS, layout)
3. Handles error if proposal page doesn't exist (404 from hex.inc)

---

### Task 2.3: Installment Calculation

**What to build in n8n:**
- Code node with the installment logic from the instructions
- Input: `total_amount`
- Output: `total_amount`, `installment_count`, `installments` array, `installment_text`

**n8n node configuration:**
- Node type: `Code`
- Language: JavaScript
- Code: exact code from the instructions document (lines 126-184)

**Test cases:**
| Input Amount | Expected Installments |
|---|---|
| $10,000 | 1: $10,000 upon signing |
| $15,000 | 1: $15,000 upon signing |
| $25,000 | 2: $15,000 + $10,000 |
| $30,000 | 2: $15,000 + $15,000 |
| $33,000 | 2: $20,000 + $13,000 (remainder <= $5k rule) |
| $35,000 | 2: $20,000 + $15,000 (remainder = $5k) |
| $40,000 | 3: $15,000 + $15,000 + $10,000 |
| $50,000 | 3: $15,000 + $15,000 + $20,000 |

**Acceptance criteria:**
1. All test cases pass
2. Edge cases handled (amount = 0, negative, etc.)
3. `installment_text` is human-readable

---

## Phase 3: Workflow 1 — Steps 8-11 (Contract + Signing + Notification)

### Task 3.1: Contract PDF Generation

**What to build in n8n:**
- HTTP Request node calling the contract generator microservice (from Task 0.2)
- Input: full deal JSON including installments
- Output: contract PDF binary

**n8n node configuration:**
- Node type: `HTTP Request`
- Method: POST
- URL: `http://contract-generator:3200/generate-contract`
- Body: full deal JSON (merged from all previous steps)
- Response format: File/Binary

**Acceptance criteria:**
1. Contract PDF is generated with all fields populated
2. `project_term_weeks` appears correctly in all 3 locations
3. Installment table is accurate
4. Professional appearance

---

### Task 3.2: Approval Gate (Email + Webhook Wait)

**What to build in n8n:**
- Gmail node: sends review email to father with deal summary + attached PDFs
- Wait node: pauses workflow until a webhook is received
- Webhook handler for approve/reject

**n8n node configuration:**
1. **Gmail node** (father's account):
   - To: father's email (self)
   - Subject: "Review: {{client_name}} contract ready"
   - Body: deal summary + installment details
   - Attachments: proposal PDF + contract PDF
   - Include approve/reject links:
     - Approve: `{{N8N_WEBHOOK_URL}}/webhook/approve?execution_id={{$execution.id}}`
     - Reject: `{{N8N_WEBHOOK_URL}}/webhook/reject?execution_id={{$execution.id}}`
2. **Wait node**:
   - Resume: On webhook call
   - Webhook suffix: unique per execution
3. **IF node** after Wait:
   - Check if approval or rejection
   - Reject → notify son, stop workflow
   - Approve → continue to Dropbox Sign

**Acceptance criteria:**
1. Father receives email with both PDFs attached
2. Clicking "Approve" link resumes the workflow
3. Clicking "Reject" link stops the workflow and notifies son
4. Wait node properly holds state

---

### Task 3.3: Dropbox Sign Signature Request

**What to build in n8n:**
- HTTP Request node calling Dropbox Sign API
- Multipart form upload with 2 documents (contract + proposal)
- Signer configuration (father = signer 0, client = signer 1)
- Field placements for signatures, initials, date fields

**n8n node configuration:**
- Node type: `HTTP Request`
- Method: POST
- URL: `https://api.hellosign.com/v3/signature_request/send`
- Auth: Basic (API key as username, empty password)
- Content-Type: multipart/form-data
- Form fields: as specified in instructions (signers, form fields with x,y coordinates)

**IMPORTANT NOTE:** Field x,y coordinates need to be determined by:
1. Generating a sample contract PDF
2. Measuring exact pixel positions of signature blocks
3. Hardcoding those coordinates (contract layout is consistent)
4. For the proposal PDF: either use consistent positions or investigate Dropbox Sign templates

**This task will likely need manual measurement and iteration.**

**Acceptance criteria:**
1. Signature request is created successfully
2. Both documents are included
3. Father receives signing request first (order: 0)
4. Client receives request after father signs (order: 1)
5. All field placements are in correct positions

---

### Task 3.4: Store Deal Context for Workflow 2

**What to build in n8n:**
- After sending the Dropbox Sign request, store the full deal context keyed by `signature_request_id`
- Use n8n's built-in static data, or write to a JSON file, or a simple SQLite database

**Recommended approach:** Use n8n's workflow static data or a Code node that writes to a shared volume:
```javascript
// Store deal context
const fs = require('fs');
const dealContext = {
  signature_request_id: signatureRequestId,
  client_name: clientName,
  contact_name: contactName,
  contact_email: contactEmail,
  plan_name: planName,
  total_amount: totalAmount,
  installments: installments,
  // ... all deal data
};
const storePath = '/data/deal-contexts/' + signatureRequestId + '.json';
fs.writeFileSync(storePath, JSON.stringify(dealContext, null, 2));
```

**Acceptance criteria:**
1. Deal context is persisted after WF1 completes
2. Context is retrievable by `signature_request_id` in WF2
3. Data survives n8n restarts (stored on persistent volume)

---

### Task 3.5: Notification to Son

**What to build in n8n:**
- Gmail node: reply to original trigger email thread
- Confirm contract was sent, include details

**Acceptance criteria:**
1. Son receives confirmation with client name, plan, amount, installment count
2. Reply is in the same email thread as the original deal notification

---

## Phase 4: Workflow 2 — Signature Complete → Onboarding

### Task 4.1: Dropbox Sign Webhook Trigger + Validation

**What to build in n8n:**
- Webhook node listening for Dropbox Sign callbacks
- IF node: validate event type is `signature_request_all_signed`
- Code node: extract `signature_request_id` from payload

**n8n node configuration:**
- Node type: `Webhook`
- Path: `/webhook/dropbox-sign-complete`
- Method: POST
- Response: return 200 immediately (Dropbox Sign expects fast acknowledgment)

**Setup required in Dropbox Sign dashboard:**
- Configure callback URL: `{{N8N_BASE_URL}}/webhook/dropbox-sign-complete`

**Acceptance criteria:**
1. Webhook receives Dropbox Sign events
2. Only processes `signature_request_all_signed` events
3. Other event types are acknowledged but not processed

---

### Task 4.2: Download Signed Documents + Retrieve Deal Context

**What to build in n8n:**
- HTTP Request: download signed PDFs from Dropbox Sign
- Code node: retrieve stored deal context from Task 3.4

**n8n nodes:**
1. HTTP Request → `GET https://api.hellosign.com/v3/signature_request/files/{{signature_request_id}}`
   - Auth: Basic
   - Response: binary/file
2. Code node → read deal context JSON from storage

**Acceptance criteria:**
1. Signed PDFs are downloaded successfully
2. Deal context is retrieved with all fields intact

---

### Task 4.3: Create QBO Customer

**What to build in n8n:**
- HTTP Request node calling QBO API to create a customer
- Use n8n's built-in QBO credential type for OAuth2 token management

**n8n node configuration:**
- Node type: `HTTP Request` (or `QuickBooks` native node if available)
- Method: POST
- URL: `https://quickbooks.api.intuit.com/v3/company/{{realm_id}}/customer`
- Auth: OAuth2 (QBO credential)
- Body: customer JSON with DisplayName, email, names, company

**Acceptance criteria:**
1. Customer is created in QBO
2. QBO customer ID is captured for subsequent steps
3. Handles duplicate customer name gracefully (QBO requires unique DisplayName)

---

### Task 4.4: Attach Signed Document to QBO Customer

**What to build in n8n:**
- HTTP Request to QBO Attachments API
- Upload signed PDF linked to the customer entity

**Acceptance criteria:**
1. Signed agreement PDF is attached to the QBO customer record
2. Attachment is visible in QBO dashboard

---

### Task 4.5: Create Client in Billing System + Map to QBO

**What to build in n8n:**
- HTTP Request → `POST /api/v1/clients` (billing system)
- HTTP Request → `POST /api/v1/clients/{id}/map-qbo` (billing system)

**Acceptance criteria:**
1. Client is created in billing system with full deal details
2. QBO customer ID is mapped to the billing system client
3. Installment schedule is stored in the billing system

---

### Task 4.6: Onboarding Notification

**What to build in n8n:**
- Gmail node: email to father confirming onboarding is complete

**Acceptance criteria:**
1. Email confirms: signed docs attached to QBO, billing configured, installment count, first invoice date

---

## Phase 5: Workflow 3 — Daily Invoice & Reminder Runner

### Task 5.1: Schedule Trigger + Fetch Unsent Invoices

**What to build in n8n:**
- Schedule Trigger: daily at 9:00 AM EST
- HTTP Request → billing system `/invoices/unsent?due_date={{today}}`
- IF node: check if any invoices exist

**n8n node configuration:**
- Schedule Trigger: Cron `0 9 * * *`, timezone `America/New_York`

**Acceptance criteria:**
1. Triggers daily at 9 AM EST
2. Correctly fetches today's unsent invoices
3. Handles empty result set (no invoices today)

---

### Task 5.2: Process Each Invoice (Generate + Send + Mark Sent)

**What to build in n8n:**
- Split In Batches node
- For each invoice:
  1. HTTP Request → billing system: generate invoice PDF
  2. HTTP Request → QBO: create + send invoice
  3. HTTP Request → billing system: mark invoice as sent

**Acceptance criteria:**
1. Each invoice is processed in sequence (no race conditions)
2. Invoice PDF is generated and sent through QBO
3. Invoice is marked as sent in billing system
4. Errors on one invoice don't stop processing of others

---

### Task 5.3: Overdue Invoice Reminders

**What to build in n8n:**
- HTTP Request → billing system `/invoices/overdue`
- Split In Batches
- Code node: determine reminder tier (1-3 days, 4-7 days, 8+ days)
- Gmail node: send appropriate reminder email
- HTTP Request → billing system: log reminder

**Reminder tiers:**
| Days Overdue | Tone | Template |
|---|---|---|
| 1-3 days | Friendly | "Just a friendly reminder that invoice #X is due..." |
| 4-7 days | Firm | "This is a reminder that invoice #X is now X days past due. Late fees may apply..." |
| 8+ days | Escalation | "Invoice #X is significantly overdue. Please arrange payment immediately..." |

**Acceptance criteria:**
1. Correct tier is selected based on days overdue
2. Emails are professional and appropriate for each tier
3. Reminders are logged to prevent duplicate sends
4. Handles case where no overdue invoices exist

---

### Task 5.4: Daily Summary Email

**What to build in n8n:**
- Gmail node: send summary to father
- Include: invoices sent count, reminders sent count, breakdown

**Acceptance criteria:**
1. Summary email sent even if no activity (reports zeros)
2. Clear breakdown of what happened

---

## Phase 6: Integration Testing & Hardening

### Task 6.1: End-to-End Test — Workflow 1

**Test procedure:**
1. Send a test email from son's account to father's account
2. Verify: trigger fires, Claude parses correctly, Gmail search works, installments calculate
3. Verify: proposal PDF generates, contract PDF generates
4. Verify: approval email arrives with attachments
5. Click approve, verify Dropbox Sign request is created
6. Verify: deal context is stored
7. Verify: notification email sent to son

---

### Task 6.2: End-to-End Test — Workflow 2

**Test procedure:**
1. Use Dropbox Sign test mode to simulate `all_signed` webhook
2. Verify: webhook triggers, signed docs download
3. Verify: QBO customer created, docs attached
4. Verify: billing system client created, QBO mapped
5. Verify: onboarding notification sent

---

### Task 6.3: End-to-End Test — Workflow 3

**Test procedure:**
1. Seed billing system with test invoices (some due today, some overdue)
2. Trigger workflow manually (or wait for schedule)
3. Verify: invoices processed, QBO invoices created
4. Verify: reminders sent for overdue invoices with correct tier
5. Verify: daily summary email accurate

---

### Task 6.4: Error Handling & Resilience

**Add to all workflows:**
- Error handling nodes (n8n Error Trigger) that email father on any workflow failure
- Retry logic on transient HTTP failures (n8n's built-in retry)
- Timeout protection on long-running nodes (especially PDF generation)
- Input validation before API calls
- Rate limiting awareness (Gmail, QBO, Claude APIs)

---

## Phase 7: Documentation & Handoff

### Task 7.1: Configuration Documentation

**Document:**
- All environment variables and where to set them
- Credential setup steps for each service (with screenshots if possible)
- Dropbox Sign webhook configuration steps
- QBO OAuth2 setup and token refresh behavior
- Docker compose startup/shutdown procedures

### Task 7.2: Operational Runbook

**Document:**
- How to monitor workflow executions in n8n
- Common failure scenarios and how to fix them
- How to manually re-run a failed workflow
- How to update the contract template
- How to add/modify installment rules
- How to change reminder email templates

---

## Effort Estimates

| Phase | Estimated Effort | Dependencies |
|---|---|---|
| Phase 0: Infrastructure | 1-2 days | Docker environment, contract template |
| Phase 1: WF1 Steps 1-4 | 1 day | Phase 0, API credentials |
| Phase 2: WF1 Steps 5-7 | 0.5 day | Phase 1 |
| Phase 3: WF1 Steps 8-11 | 1-2 days | Phase 2, Dropbox Sign field measurement |
| Phase 4: WF2 | 1 day | Phase 3, QBO credentials |
| Phase 5: WF3 | 0.5-1 day | Billing system API |
| Phase 6: Testing | 1-2 days | All phases |
| Phase 7: Docs | 0.5 day | All phases |
| **Total** | **~6-9 days** | |

---

## Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| Billing system API not ready | Blocks WF2 + WF3 | Verify before starting; mock if needed |
| Dropbox Sign field coordinates wrong | Signatures in wrong positions | Generate test PDFs, measure carefully, iterate |
| QBO OAuth2 token refresh fails | Invoicing breaks | Monitor token health, set up alerts |
| hex.inc proposal page changes layout | Proposal PDFs break | Monitor; consider caching rendered PDFs |
| Gmail API rate limits | Missed triggers or sends | Use poll (not push) for trigger; batch sends |
| Claude Haiku misparses email | Wrong deal data flows through | Approval gate (Step 9) catches this; also add data validation |

---

## How to Use This Plan

**For each task:**
1. Read the task description, acceptance criteria, and implementation details
2. Implement the described component
3. Test against the acceptance criteria
4. Move to the next task

**Tasks within a phase are sequential.** Phases can overlap where dependencies allow (e.g., Phase 5 can start as soon as Phase 0 is done if the billing system is ready).

**The approval gate in WF1 (Task 3.2) is the critical safety net** — it ensures no contract goes out without the father reviewing it, which protects against AI parsing errors or template issues.
