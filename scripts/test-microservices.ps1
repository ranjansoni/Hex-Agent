# Test pdf-renderer and contract-generator. Run after: docker-compose up -d
# Usage: .\scripts\test-microservices.ps1 [-BaseUrl "http://localhost"] [-OutDir ".\test-output"]

param(
    [string]$BaseUrl = "http://localhost",
    [string]$OutDir = ".\test-output"
)

$Renderer = $BaseUrl + ":3100"
$Contract = $BaseUrl + ":3200"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Write-Host "=== Testing microservices (renderer: $Renderer, contract: $Contract) ===" -ForegroundColor Cyan

# 1. Health checks
Write-Host "`n1. Health: pdf-renderer..."
try {
    Invoke-WebRequest -Uri "$Renderer/health" -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host "   OK" -ForegroundColor Green
} catch {
    Write-Host "   FAIL" -ForegroundColor Red
    exit 1
}

Write-Host "2. Health: contract-generator..."
try {
    Invoke-WebRequest -Uri "$Contract/health" -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host "   OK" -ForegroundColor Green
} catch {
    Write-Host "   FAIL" -ForegroundColor Red
    exit 1
}

# 3. Contract PDF
Write-Host "`n3. POST /generate-contract (sample deal)..."
$contractJson = @'
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
'@
try {
    $r = Invoke-WebRequest -Uri "$Contract/generate-contract" -Method POST `
        -ContentType "application/json" -Body $contractJson -UseBasicParsing -TimeoutSec 30
    $path = Join-Path $OutDir "contract.pdf"
    [IO.File]::WriteAllBytes($path, $r.Content)
    Write-Host "   OK -> $path ($($r.Content.Length) bytes)" -ForegroundColor Green
} catch {
    Write-Host "   FAIL" -ForegroundColor Red
    exit 1
}

# 4. Proposal PDF
Write-Host "`n4. POST /render-pdf (example.com)..."
try {
    $r = Invoke-WebRequest -Uri "$Renderer/render-pdf" -Method POST `
        -ContentType "application/json" -Body '{"url":"https://example.com"}' -UseBasicParsing -TimeoutSec 35
    $path = Join-Path $OutDir "proposal-example.pdf"
    [IO.File]::WriteAllBytes($path, $r.Content)
    Write-Host "   OK -> $path ($($r.Content.Length) bytes)" -ForegroundColor Green
} catch {
    Write-Host "   FAIL" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== All checks passed. ===" -ForegroundColor Green
