#!/usr/bin/env bash
# Run the "Hex – Invoice from email (revised scope)" workflow via n8n CLI.
# Requires: n8n running (docker compose up -d), workflow already imported in n8n.
#
# Gmail credentials cannot be set via script (OAuth needs browser). Configure them
# once in n8n UI (http://localhost:5678) on the Gmail Trigger and Reply nodes.
#
# Usage: ./scripts/test-invoice-workflow.sh

set -e
WORKFLOW_NAME="Hex – Invoice from email (revised scope)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Resolve n8n container (docker compose project name from directory)
CONTAINER=$(docker compose ps -q n8n 2>/dev/null || true)
if [ -z "$CONTAINER" ]; then
  echo "Error: n8n container not running. Start with: docker compose up -d"
  exit 1
fi

echo "=== n8n: run invoice-from-email workflow ==="
echo "Container: $CONTAINER"
echo ""

# Export all workflows (stdout), find this workflow's id
echo "Finding workflow: $WORKFLOW_NAME"
EXPORT=$(docker exec "$CONTAINER" n8n export:workflow --all 2>/dev/null)

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

WF_ID=$(echo "$EXPORT" | jq -r --arg name "$WORKFLOW_NAME" '.[] | select(.name == $name) | .id')
if [ -z "$WF_ID" ] || [ "$WF_ID" = "null" ]; then
  echo "Error: Workflow not found. Import it first:"
  echo "  n8n UI -> Workflows -> Import from File -> workflows/hex-invoice-from-email.json"
  echo "  Or: docker exec -u node -it $CONTAINER n8n import:workflow --input=/path/to/hex-invoice-from-email.json"
  exit 1
fi

echo "Workflow ID: $WF_ID"
echo "Executing..."
echo ""

docker exec -u node "$CONTAINER" n8n execute --id "$WF_ID"

echo ""
echo "Done. Check n8n UI (http://localhost:5678) for execution result."
echo "If Gmail nodes failed, set Gmail OAuth2 credentials once in the UI."
