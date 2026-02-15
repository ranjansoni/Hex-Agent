#!/usr/bin/env bash
# Test pdf-renderer and contract-generator. Run after: docker-compose up -d
# Usage: ./scripts/test-microservices.sh [base_url]
# Default base_url: http://localhost

set -e
BASE="${1:-http://localhost}"
RENDERER="${BASE}:3100"
CONTRACT="${BASE}:3200"
OUTDIR="${2:-./test-output}"
mkdir -p "$OUTDIR"

echo "=== Testing microservices (renderer: $RENDERER, contract: $CONTRACT) ==="

# 1. Health checks
echo ""
echo "1. Health: pdf-renderer..."
if curl -sf "$RENDERER/health" > /dev/null; then
  echo "   OK"
else
  echo "   FAIL"
  exit 1
fi

echo "2. Health: contract-generator..."
if curl -sf "$CONTRACT/health" > /dev/null; then
  echo "   OK"
else
  echo "   FAIL"
  exit 1
fi

# 3. Contract PDF
echo ""
echo "3. POST /generate-contract (sample deal)..."
CONTRACT_JSON='{
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
}'
if curl -sf -X POST "$CONTRACT/generate-contract" \
  -H "Content-Type: application/json" \
  -d "$CONTRACT_JSON" \
  -o "$OUTDIR/contract.pdf"; then
  echo "   OK -> $OUTDIR/contract.pdf ($(wc -c < "$OUTDIR/contract.pdf") bytes)"
else
  echo "   FAIL"
  exit 1
fi

# 4. Proposal PDF (render a public URL; use example.com if you don't have hex.inc)
echo ""
echo "4. POST /render-pdf (example.com to verify renderer)..."
if curl -sf -X POST "$RENDERER/render-pdf" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}' \
  -o "$OUTDIR/proposal-example.pdf"; then
  echo "   OK -> $OUTDIR/proposal-example.pdf ($(wc -c < "$OUTDIR/proposal-example.pdf") bytes)"
else
  echo "   FAIL (timeout or error)"
  exit 1
fi

echo ""
echo "=== All checks passed. ==="
