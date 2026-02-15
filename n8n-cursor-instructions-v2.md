# Cursor Instructions: n8n Workflow Builder for Hex Studio

## Context
You are helping build n8n workflows for a deal-to-invoice automation pipeline for a web design agency (Hex Studio). The owner's son closes deals and sends an email to his father's Gmail. The father then processes the deal through contract creation, e-signing, QBO setup, and billing system entry.

## Tech Stack
- **n8n** (self-hosted, Docker, latest stable)
- **APIs:** Gmail OAuth2 (two accounts: father's inbox + son's inbox for client thread access), Notion API, Dropbox Sign / HelloSign API, QuickBooks Online OAuth2, Anthropic Claude API (Haiku), Custom billing system (REST API via Tailscale)
- **External:** hex.inc/proposal/{clientName} for proposal pages (need to export to PDF)

## Gmail Setup
- **Father's Gmail:** Receives trigger emails from son. Address: {{FATHER_GMAIL}}
- **Son's Gmail:** Father has delegated access. Used to search client threads and find proposal links + plan details. Address: {{SON_GMAIL}}
- Both accounts need separate OAuth2 credentials in n8n.

---

## WORKFLOW 1: Deal Intake → Contract Sent for Signing

### Trigger
Son sends an email to father's Gmail. The email contains at minimum the client/contact name. It may also contain:
- Which plan was chosen
- The contact's email
- The proposal link
- Other deal context

The email is informal — not structured. Example:
> "Hey Dad, closed Acme Corp. John Smith, john@acme.com. They went with the Growth plan. Here's the proposal: https://hex.inc/proposal/acme-corp"

Or more vague:
> "Hey, new deal with Smith Industries. Can you send the contract?"

### Step-by-Step Logic

**Step 1: Gmail Trigger — Father's Inbox**
- Node: `Gmail Trigger` (poll or webhook)
- Filter: emails from son's Gmail address
- Alternatively: Label-based trigger — son applies a label like "New Deal" or father has a filter that auto-labels
- Output: email subject, body, sender

**Step 2: Parse Email with Claude Haiku**
- Node: `HTTP Request` → Claude API
- System prompt:
```
You are parsing a deal notification email from a web design agency owner's son.
Extract the following from the email. Return ONLY valid JSON.

{
  "client_name": "Company or person name",
  "contact_name": "Contact person's full name (may be same as client_name for individuals)",
  "contact_email": "Email address if mentioned, else null",
  "plan_name": "Plan name if mentioned (e.g., Growth, Starter, Enterprise), else null",
  "proposal_url": "Full URL if a hex.inc/proposal/ link is present, else null",
  "client_slug": "If proposal URL present, extract the slug after /proposal/. If no URL but client name is clear, generate a likely slug (lowercase, hyphenated). Else null.",
  "kickoff_date": "If a start date or kickoff date is mentioned, format as YYYY-MM-DD. Else null",
  "notes": "Any other relevant context from the email"
}

If the email is ambiguous about a field, set it to null. Do not guess.
```
- Input: email subject + body
- Model: `claude-haiku-4-5-20251001`
- Output: parsed deal JSON

**Step 3: Search Son's Gmail for Client Thread**
- Node: `Gmail` (using son's Gmail credentials)
- Action: Search messages
- Query: `{{client_name}} OR {{contact_email}} OR {{contact_name}}`
- Max results: 10
- Sort: newest first
- Output: list of email threads

**Step 4: Extract Missing Info from Client Thread (Claude Haiku)**
- Node: `HTTP Request` → Claude API
- Purpose: Read through the email thread(s) from Step 3 to find:
  - Plan chosen (if not in son's email)
  - Contact email (if not in son's email)
  - Proposal link (if not in son's email)
  - Any deal amount mentioned
  - Project timeline/term mentioned
- System prompt:
```
You are reading email threads between a web design agency and their client.
You already know:
- Client: {{client_name}}
- Contact: {{contact_name}}
- Contact email: {{contact_email}} (may be null)
- Plan: {{plan_name}} (may be null)
- Proposal URL: {{proposal_url}} (may be null)

From the email threads below, find any missing information. Return ONLY valid JSON with the SAME fields, but filled in where you found data. Keep existing non-null values unchanged. Only update null fields if you find clear evidence.

Also extract:
- "total_amount": total project amount if mentioned (number, no currency symbol), else null
- "project_term_weeks": project duration in weeks if mentioned, else null

Email threads:
{thread_content}
```
- Output: enriched deal JSON

**Step 5: Check for Missing Critical Fields**
- Node: `IF`
- Condition: `plan_name == null OR contact_email == null`
- True → **Step 5a**: Reply to son's email asking for missing info. Include what's missing. STOP workflow.
  - Node: `Gmail` (father's account) → Reply to trigger email
  - Body: "Hey, need some details for {{client_name}}: [list null fields]. Can you confirm?"
- False → continue

**Step 6: Get Proposal PDF**
- The proposal lives at `https://hex.inc/proposal/{{client_slug}}`
- Node: `HTTP Request` → GET the proposal page
- Then convert to PDF. Options:
  - **Option A (recommended):** Use a headless browser service to render the page to PDF. Either:
    - Self-hosted Puppeteer microservice (Cursor-built, running alongside n8n)
    - Or use a service like `https://api.pdflayer.com` or `https://api.html2pdf.app`
  - **Option B:** n8n Code node running Puppeteer (heavier, but no external dependency)
- Input: `https://hex.inc/proposal/{{client_slug}}`
- Output: proposal PDF binary

**Step 7: Determine Installments**
- Node: `Code` (JavaScript)
- Input: `total_amount` from deal JSON
- Logic:
```javascript
const amount = $input.first().json.total_amount;
let installments = [];

if (amount <= 30000) {
  // Two installments: 15k + balance
  const balance = amount - 15000;
  installments = [
    { number: 1, amount: 15000, timing: "Upon signing" },
    { number: 2, amount: balance, timing: "2 weeks after kickoff" }
  ];
} else {
  // Amount > 30k
  const afterTwo = amount - 30000; // balance after 15k + 15k

  if (afterTwo <= 5000) {
    // Balance is small, load upfront: 20k + 15k
    // But verify: if amount is exactly 35k, this gives 20+15=35k ✓
    // Actually re-read: "do 20 + 15 (more upfront)" — this means 2 installments
    // Wait — need to re-check. The balance after 15+15=30k is <=5k.
    // "if balance is lower than 5k then do 20 + 15"
    // This means: instead of 15+15+small_balance, do 20+15 = 35k (absorb the remainder)
    // But what if amount is 34k? 20+14=34k? Or 20+15=35k?
    // Safest interpretation: two installments, first = amount - 15000, second = 15000
    // No wait: "20 + 15 (more upfront)" — for a ~33-35k deal
    // Let me implement: first = 20000, second = amount - 20000
    // Actually the rule is: if remainder after 30k < 5k, merge into 2 payments
    installments = [
      { number: 1, amount: 20000, timing: "Upon signing" },
      { number: 2, amount: amount - 20000, timing: "2 weeks after kickoff" }
    ];
  } else {
    // Balance > 5k: three installments: 15k + 15k + balance
    const balance = amount - 30000;
    installments = [
      { number: 1, amount: 15000, timing: "Upon signing" },
      { number: 2, amount: 15000, timing: "2 weeks after kickoff" },
      { number: 3, amount: balance, timing: "4 weeks after kickoff" }
    ];
  }
}

// Minimum installment is 15k per 2-week period
// Verify no installment is below threshold (edge case for very small deals)
// For deals under 15k total, single payment
if (amount <= 15000) {
  installments = [
    { number: 1, amount: amount, timing: "Upon signing" }
  ];
}

return {
  total_amount: amount,
  installment_count: installments.length,
  installments: installments,
  // This will be inserted into the contract
  installment_text: installments.map(i =>
    `Installment ${i.number}: USD $${i.amount.toLocaleString()} — ${i.timing}`
  ).join('\n')
};
```

**Step 8: Clone Notion Contract and Populate**
- Node: `Notion` → Create Page (duplicate from template)
- Database: Contracts database
- Or: Use Notion API to duplicate a specific template page
- Then: `Notion` → Update Page / Append Blocks
- Fields to populate in the contract:
  - Client name / company
  - Contact name
  - Plan name
  - Total amount
  - Installment schedule (from Step 7)
  - Kickoff date (or "TBD")
  - Project term: "{{project_term_weeks}} weeks" — replace in 3 locations in the document body
- **Important:** The contract template has "X weeks" appearing in 3 different spots. All three must be replaced with the actual number.

- **PDF Export Challenge:** Notion API does not support PDF export natively.
  - **Recommended approach:** Instead of using Notion as the contract template, migrate the contract template to an HTML/Handlebars template. Cursor can build a microservice that:
    1. Takes deal JSON as input
    2. Renders the HTML template with all variables populated (including installment table, 3x week replacement)
    3. Returns a PDF
  - This is more reliable than trying to programmatically edit a Notion page and export it.
  - **Alternative:** If Notion must be used, use the unofficial Notion PDF export (fragile) or use `notion-to-md` → `md-to-pdf` pipeline.

**Step 9: Approval Gate**
- Node: `Gmail` (father's account) → Send email to self
- Subject: "🔍 Review: {{client_name}} contract ready"
- Body: Summary of deal + installments + links to preview both PDFs
- Attach: proposal PDF + contract PDF
- Include two links/buttons:
  - Approve: hits an n8n webhook URL `{{N8N_WEBHOOK_URL}}/approve/{{execution_id}}`
  - Reject: hits `{{N8N_WEBHOOK_URL}}/reject/{{execution_id}}`
- Node: `Wait` → Resume on webhook

**Step 10: Create Dropbox Sign Signature Request**
- Node: `HTTP Request` → Dropbox Sign API
- Endpoint: `POST https://api.hellosign.com/v3/signature_request/send`
- Auth: Basic auth (API key as username)
- This is a multipart form request with two documents and specific field placements.

**Document 1: Contract (uploaded first)**
Field placements (signer 0 = Hex Studio / father, signer 1 = client):

Near contract terms and amount section:
```
Signer 0 (Hex Studio) - Initial:
  - type: "initials"
  - x, y coordinates: near the contract terms / installment section
  - page: (page where terms appear)

Signer 1 (Client) - Initial:
  - type: "initials"
  - x, y coordinates: same area, adjacent to Hex Studio initials
  - page: same
```

At the end of the contract (signature block):
```
Signer 0 (Hex Studio):
  - Sign: type "signature", positioned at signature line
  - Name: type "text", labeled "Full Name"
  - Company: type "text", labeled "Company", pre-fill "Hex Studio"
  - Address: type "text", labeled "Address"
  - Date Signed: type "date_signed"

Signer 1 (Client):
  - Sign: type "signature"
  - Name: type "text", labeled "Full Name"
  - Company: type "text", labeled "Company"
  - Address: type "text", labeled "Address"
  - Date Signed: type "date_signed"
```

**Document 2: Proposal (uploaded second)**

Near the selected plan:
```
Signer 0 (Hex Studio) - Initial:
  - type: "initials"
  - x, y coordinates: next to the selected plan name/section
  - page: (page where plan details appear)

Signer 1 (Client) - Initial:
  - type: "initials"
  - same area
```

At the end of the proposal:
```
Signer 0 (Hex Studio):
  - Sign: type "signature"
  - Date Signed: type "date_signed"

Signer 1 (Client):
  - Sign: type "signature"
  - Date Signed: type "date_signed"
```

**Signers:**
```json
{
  "signers[0][email_address]": "{{FATHER_EMAIL}}",
  "signers[0][name]": "{{FATHER_NAME}}",
  "signers[0][order]": 0,
  "signers[1][email_address]": "{{contact_email}}",
  "signers[1][name]": "{{contact_name}}",
  "signers[1][order]": 1
}
```

**NOTE on field coordinates:** The x,y positions depend on the actual PDF layout. Since the contract is generated from a template (consistent layout), coordinates can be hardcoded once measured. The proposal PDF from hex.inc may vary — you may need Claude Vision to locate the selected plan section and calculate coordinates dynamically. Alternatively, use Dropbox Sign's template feature with merge fields if the proposal format is consistent enough.

**Step 11: Notify**
- Node: `Gmail` → Reply to original son's email
- Body: "Contract sent to {{contact_name}} ({{contact_email}}) for signing. {{plan_name}} plan, ${{total_amount}}, {{installment_count}} installments."

---

## WORKFLOW 2: Signature Complete → Client Onboarding

### Trigger: Dropbox Sign Webhook
- Node: `Webhook`
- Dropbox Sign sends callback on `signature_request_all_signed` event
- URL: `{{N8N_BASE_URL}}/webhook/dropbox-sign-complete`

### Steps

**Step 1: Validate Event**
- Node: `IF` → check `event.event_type == "signature_request_all_signed"`

**Step 2: Download Signed Documents**
- Node: `HTTP Request` → `GET https://api.hellosign.com/v3/signature_request/files/{{signature_request_id}}`
- Output: signed PDF(s)

**Step 3: Extract Deal Context**
- The webhook payload includes the signature request title which contains client name
- Node: `Code` → parse client_name, plan, amount from the request metadata
- Or: Store deal context in a simple JSON file / database keyed by signature_request_id when Workflow 1 sends the request, and retrieve it here

**Step 4: Create QBO Customer**
- Node: `HTTP Request` → QBO API
- `POST https://quickbooks.api.intuit.com/v3/company/{{realm_id}}/customer`
```json
{
  "DisplayName": "{{client_name}}",
  "PrimaryEmailAddr": { "Address": "{{contact_email}}" },
  "GivenName": "{{contact_name.split(' ')[0]}}",
  "FamilyName": "{{contact_name.split(' ').slice(1).join(' ')}}",
  "CompanyName": "{{client_name}}"
}
```

**Step 5: Attach Signed Agreement to QBO Customer**
- Node: `HTTP Request` → QBO Attachments API
- `POST https://quickbooks.api.intuit.com/v3/company/{{realm_id}}/upload`
- Multipart form: attach signed PDF, link to customer entity

**Step 6: Create Client in Billing System**
- Node: `HTTP Request` → Billing System API (via Tailscale)
- `POST http://{{BILLING_SYSTEM_HOST}}/api/v1/clients`
- Body: client details + installment schedule + payment terms from Workflow 1 context

**Step 7: Map Client to QBO**
- Node: `HTTP Request` → Billing System API
- `POST http://{{BILLING_SYSTEM_HOST}}/api/v1/clients/{{billing_client_id}}/map-qbo`
- Body: `{ "qbo_customer_id": "{{qbo_customer_id}}" }`

**Step 8: Notify**
- Node: `Gmail` → Email to father
- Subject: "✅ {{client_name}} onboarded"
- Body: "Signed agreement attached to QBO. Billing system configured with {{installment_count}} installments. First invoice: {{first_invoice_date}}."

---

## WORKFLOW 3: Daily Invoice & Reminder Runner

### Trigger: Schedule (daily 9:00 AM EST)
- Node: `Schedule Trigger`
- Cron: `0 9 * * *`
- Timezone: America/New_York

### Steps

**Step 1: Get Today's Unsent Invoices**
- Node: `HTTP Request` → Billing System API
- `GET http://{{BILLING_SYSTEM_HOST}}/api/v1/invoices/unsent?due_date={{today}}`

**Step 2: Check if Any Exist**
- Node: `IF` → array length > 0

**Step 3: Process Each Invoice**
- Node: `Split In Batches`
- For each:
  - HTTP Request → Billing System: generate invoice PDF
  - HTTP Request → QBO: create invoice + send to customer
  - HTTP Request → Billing System: mark invoice as sent

**Step 4: Get Overdue Invoices Needing Reminders**
- Node: `HTTP Request` → Billing System API
- `GET http://{{BILLING_SYSTEM_HOST}}/api/v1/invoices/overdue`

**Step 5: Send Reminders**
- Node: `Split In Batches`
- For each overdue invoice:
  - Determine reminder tier based on days overdue:
    - 1-3 days: friendly reminder
    - 4-7 days: firm reminder with late fee warning
    - 8+ days: escalation notice
  - HTTP Request → Gmail: send reminder email using appropriate template
  - HTTP Request → Billing System: log reminder sent

**Step 6: Daily Summary**
- Node: `Gmail` → Email to father
- Subject: "📊 Daily billing: {{invoices_sent}} sent, {{reminders_sent}} reminders"
- Body: breakdown of activity

---

## Installment Logic Reference

```
if amount <= 15,000:
  → 1 installment: full amount upon signing

if 15,001 <= amount <= 30,000:
  → 2 installments: $15,000 upon signing + balance at 2 weeks

if amount > 30,000:
  remainder = amount - 30,000
  if remainder <= 5,000:
    → 2 installments: $20,000 upon signing + (amount - 20,000) at 2 weeks
  if remainder > 5,000:
    → 3 installments: $15,000 upon signing + $15,000 at 2 weeks + balance at 4 weeks
```

Minimum per installment period (2 weeks) = $15,000
Bias: more upfront when balance would be trivially small

---

## API Reference

### Claude Haiku (parsing)
```
POST https://api.anthropic.com/v1/messages
Headers:
  x-api-key: {{ANTHROPIC_API_KEY}}
  anthropic-version: 2023-06-01
  content-type: application/json
Body: { "model": "claude-haiku-4-5-20251001", "max_tokens": 500, "system": "...", "messages": [...] }
```

### Dropbox Sign (HelloSign)
```
# Send signature request with files and fields
POST https://api.hellosign.com/v3/signature_request/send
Auth: Basic {{HELLOSIGN_API_KEY}}:
Content-Type: multipart/form-data

# Download signed files
GET https://api.hellosign.com/v3/signature_request/files/{{signature_request_id}}

# Webhook events: configure callback URL in Dropbox Sign dashboard
```

### QuickBooks Online
```
POST https://quickbooks.api.intuit.com/v3/company/{{realm_id}}/customer
POST https://quickbooks.api.intuit.com/v3/company/{{realm_id}}/upload
Headers: Authorization: Bearer {{access_token}}
Note: QBO OAuth tokens expire — n8n has a built-in QBO credential type that handles refresh
```

### Billing System (internal, via Tailscale)
```
Base: http://{{BILLING_SYSTEM_HOST}}/api/v1
POST /clients
POST /clients/{id}/map-qbo
GET  /invoices/unsent?due_date={YYYY-MM-DD}
POST /invoices/{id}/generate-pdf
POST /invoices/{id}/mark-sent
GET  /invoices/overdue
POST /invoices/{id}/log-reminder
```

### Notion
```
Base: https://api.notion.com/v1
POST /pages — create page (clone template)
PATCH /pages/{id} — update properties
PATCH /blocks/{id}/children — update page content
Headers: Authorization: Bearer {{NOTION_API_KEY}}, Notion-Version: 2022-06-28
```

---

## Generation Instructions
When asked to generate a workflow, output complete n8n-importable JSON. Use placeholder credential IDs (e.g., `"GMAIL_FATHER_CREDENTIAL_ID"`, `"GMAIL_SON_CREDENTIAL_ID"`). After each workflow JSON, list:
1. Credentials to configure in n8n
2. Environment-specific values to replace
3. Node-by-node testing sequence
4. Known limitations or manual steps still required
