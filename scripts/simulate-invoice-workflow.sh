#!/usr/bin/env bash
# Simulate the "Hex – Invoice from email" workflow against the billing API.
# Verifies all endpoints the workflow uses and optionally runs a full pass with a client name.
#
# Usage:
#   BILLING_BASE_URL=https://billing-test.hex.inc N8N_API_SECRET=your_secret ./scripts/simulate-invoice-workflow.sh
#   BILLING_BASE_URL=... N8N_API_SECRET=... ./scripts/simulate-invoice-workflow.sh "Client Name"
#
# Env (required): BILLING_BASE_URL, N8N_API_SECRET
# Optional arg: client name (partial match) to test find-client + create-invoice path.

set -e
CLIENT_NAME="${1:-}"
BASE="${BILLING_BASE_URL:?Set BILLING_BASE_URL (e.g. https://billing-test.hex.inc)}"
SECRET="${N8N_API_SECRET:?Set N8N_API_SECRET}"
AUTH_HEADER="Authorization: Bearer $SECRET"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

echo "=== Simulating invoice-from-email workflow ==="
echo "Base URL: $BASE"
echo "Client name (optional): ${CLIENT_NAME:-<none>}"
echo ""

# 1. GET /api/clients
echo "1. GET /api/clients"
CLIENTS_RESP=$(curl -sfL -w "\n%{http_code}" -H "$AUTH_HEADER" "$BASE/api/clients")
HTTP_CODE=$(echo "$CLIENTS_RESP" | tail -n1)
CLIENTS_JSON=$(echo "$CLIENTS_RESP" | sed '$d')
if [ "$HTTP_CODE" != "200" ]; then
  echo "   FAIL (HTTP $HTTP_CODE)"
  echo "$CLIENTS_JSON" | jq . 2>/dev/null || echo "$CLIENTS_JSON"
  exit 1
fi
if ! echo "$CLIENTS_JSON" | jq -e . &>/dev/null; then
  echo "   FAIL (response not JSON; auth or route may be wrong)"
  echo "   First 200 chars: $(echo "$CLIENTS_JSON" | head -c 200)"
  exit 1
fi
# Normalize: API might return { data: [...] } or direct array
if echo "$CLIENTS_JSON" | jq -e '.data' &>/dev/null; then
  CLIENTS_ARR=$(echo "$CLIENTS_JSON" | jq -c '.data')
else
  CLIENTS_ARR=$(echo "$CLIENTS_JSON" | jq -c 'if type == "array" then . else [.] end')
fi
COUNT=$(echo "$CLIENTS_ARR" | jq 'length')
echo "   OK ($COUNT clients)"

# 2. Find client by partial name (same logic as workflow)
CLIENT_ID=""
if [ -n "$CLIENT_NAME" ]; then
  echo ""
  echo "2. Find client by name: \"$CLIENT_NAME\""
  SEARCH=$(echo "$CLIENT_NAME" | tr '[:upper:]' '[:lower:]' | xargs)
  CLIENT_ID=$(echo "$CLIENTS_ARR" | jq -r --arg s "$SEARCH" '
    .[] | (.name // .companyName // "") as $n | ($n | ascii_downcase) as $lower
    | select(($lower != "") and (($lower | index($s)) or ($s | index($lower))))
    | .id
  ' | head -n1)
  if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
    echo "   No match. You can test create-client + create-invoice by using an exact name from the list."
    echo "   First 5 client names:"
    echo "$CLIENTS_ARR" | jq -r '.[0:5][] | "     - \(.name // .companyName // .id)"'
  else
    echo "   OK clientId=$CLIENT_ID"
  fi
fi

# 3. POST /api/invoices (if we have a client)
if [ -n "$CLIENT_ID" ] && [ "$CLIENT_ID" != "null" ]; then
  echo ""
  echo "3. POST /api/invoices (clientId=$CLIENT_ID)"
  TODAY=$(date +%Y-%m-%d)
  BODY=$(jq -nc \
    --arg cid "$CLIENT_ID" \
    --arg today "$TODAY" \
    '{ clientId: ($cid | tonumber), stage: "From n8n", amount: 0, plannedInvoiceDate: $today, okayToInvoice: false, invoiced: false }')
  INV_RESP=$(curl -sfL -w "\n%{http_code}" -X POST "$BASE/api/invoices" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" -d "$BODY")
  INV_HTTP=$(echo "$INV_RESP" | tail -n1)
  INV_JSON=$(echo "$INV_RESP" | sed '$d')
  if [ "$INV_HTTP" != "200" ] && [ "$INV_HTTP" != "201" ]; then
    echo "   FAIL (HTTP $INV_HTTP)"
    echo "$INV_JSON" | jq . 2>/dev/null || echo "$INV_JSON"
  else
    CREATED_ID=$(echo "$INV_JSON" | jq -r '.id // .data.id // empty')
    echo "   OK invoice id=$CREATED_ID"
  fi
fi

# 4. GET /api/invoices/unsent
echo ""
echo "4. GET /api/invoices/unsent?due_date=$(date +%Y-%m-%d)"
UNSENT_RESP=$(curl -sfL -w "\n%{http_code}" -H "$AUTH_HEADER" "$BASE/api/invoices/unsent?due_date=$(date +%Y-%m-%d)")
UNSENT_HTTP=$(echo "$UNSENT_RESP" | tail -n1)
UNSENT_JSON=$(echo "$UNSENT_RESP" | sed '$d')
if [ "$UNSENT_HTTP" != "200" ]; then
  echo "   FAIL (HTTP $UNSENT_HTTP)"
  echo "$UNSENT_JSON" | jq . 2>/dev/null || echo "$UNSENT_JSON"
else
  UNSENT_COUNT=$(echo "$UNSENT_JSON" | jq 'if type == "array" then length else (.data | length) end' 2>/dev/null || echo "0")
  echo "   OK (unsent today: $UNSENT_COUNT)"
fi

# 5. GET /api/invoices/overdue
echo ""
echo "5. GET /api/invoices/overdue"
OVERDUE_RESP=$(curl -sfL -w "\n%{http_code}" -H "$AUTH_HEADER" "$BASE/api/invoices/overdue")
OVERDUE_HTTP=$(echo "$OVERDUE_RESP" | tail -n1)
OVERDUE_JSON=$(echo "$OVERDUE_RESP" | sed '$d')
if [ "$OVERDUE_HTTP" != "200" ]; then
  echo "   FAIL (HTTP $OVERDUE_HTTP)"
  echo "$OVERDUE_JSON" | jq . 2>/dev/null || echo "$OVERDUE_JSON"
else
  OVERDUE_COUNT=$(echo "$OVERDUE_JSON" | jq 'if type == "array" then length else (.data | length) end' 2>/dev/null || echo "0")
  echo "   OK (overdue count: $OVERDUE_COUNT)"
fi

# 6. POST /api/invoices/:id/log-reminder (if we have an invoice id)
if [ -n "${CREATED_ID:-}" ] && [ "$CREATED_ID" != "null" ]; then
  echo ""
  echo "6. POST /api/invoices/$CREATED_ID/log-reminder"
  REMIND_RESP=$(curl -sL -w "\n%{http_code}" -X POST "$BASE/api/invoices/$CREATED_ID/log-reminder" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" -d '{"reminderTier":"test","daysOverdue":0}')
  REMIND_HTTP=$(echo "$REMIND_RESP" | tail -n1)
  if [ "$REMIND_HTTP" != "200" ] && [ "$REMIND_HTTP" != "201" ] && [ "$REMIND_HTTP" != "204" ]; then
    echo "   FAIL (HTTP $REMIND_HTTP)"
    echo "$REMIND_RESP" | sed '$d' | jq . 2>/dev/null || echo "$REMIND_RESP" | sed '$d'
  else
    echo "   OK"
  fi
else
  echo ""
  echo "6. POST /api/invoices/:id/log-reminder (skipped: no invoice id from step 3)"
fi

echo ""
echo "=== All requested checks finished ==="
echo "Provide a client name as first argument to test find + create-invoice:"
echo "  BILLING_BASE_URL=... N8N_API_SECRET=... $0 \"Your Client Name\""
