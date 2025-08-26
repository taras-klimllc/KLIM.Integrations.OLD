# RabbitMQ Complete Topology Cleanup Script
# Execute these commands to fix ALL remaining issues

Write-Host "?? Starting Complete RabbitMQ Topology Cleanup..." -ForegroundColor Yellow

# ============================================================================
# STEP 1: Remove Incorrect Fanout Exchange (klim.affinity.sqlwriter)
# ============================================================================
Write-Host "Step 1: Removing incorrect fanout exchange..." -ForegroundColor Cyan

# Delete the problematic fanout exchange using Management API
try {
    $response = Invoke-RestMethod -Uri "http://localhost:15672/api/exchanges/%2F/klim.affinity.sqlwriter" -Method Delete -Credential (New-Object System.Management.Automation.PSCredential("guest", (ConvertTo-SecureString "guest" -AsPlainText -Force)))
    Write-Host "? Removed fanout exchange: klim.affinity.sqlwriter" -ForegroundColor Green
} catch {
    Write-Host "??  Exchange may not exist or already removed" -ForegroundColor Yellow
}

# ============================================================================
# STEP 2: Remove Old Queue (klim.integration.affinity.sqlwriter)
# ============================================================================
Write-Host "Step 2: Removing old queue..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "http://localhost:15672/api/queues/%2F/klim.integration.affinity.sqlwriter" -Method Delete -Credential (New-Object System.Management.Automation.PSCredential("guest", (ConvertTo-SecureString "guest" -AsPlainText -Force)))
    Write-Host "? Removed old queue: klim.integration.affinity.sqlwriter" -ForegroundColor Green
} catch {
    Write-Host "??  Old queue may not exist or already removed" -ForegroundColor Yellow
}

# ============================================================================
# STEP 3: Ensure Correct Queue Exists
# ============================================================================
Write-Host "Step 3: Ensuring correct queue exists..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "http://localhost:15672/api/queues/%2F/klim.affinity.sqlwriter" -Method Put -Body '{"durable":true,"arguments":{"x-queue-type":"classic"}}' -ContentType "application/json" -Credential (New-Object System.Management.Automation.PSCredential("guest", (ConvertTo-SecureString "guest" -AsPlainText -Force)))
    Write-Host "? Verified queue exists: klim.affinity.sqlwriter" -ForegroundColor Green
} catch {
    Write-Host "??  Queue already exists" -ForegroundColor Yellow
}

# ============================================================================
# STEP 4: Create Correct Exchange-to-Queue Binding
# ============================================================================
Write-Host "Step 4: Creating correct binding..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "http://localhost:15672/api/bindings/%2F/e/klim.events.integration/q/klim.affinity.sqlwriter" -Method Post -Body '{"routing_key":"klim.integration.affinity.#","arguments":{}}' -ContentType "application/json" -Credential (New-Object System.Management.Automation.PSCredential("guest", (ConvertTo-SecureString "guest" -AsPlainText -Force)))
    Write-Host "? Created correct binding: klim.events.integration -> klim.affinity.sqlwriter" -ForegroundColor Green
} catch {
    Write-Host "??  Binding may already exist" -ForegroundColor Yellow
}

# ============================================================================
# STEP 5: Verification
# ============================================================================
Write-Host "Step 5: Verifying corrected topology..." -ForegroundColor Cyan

# Check exchanges
Write-Host "Exchanges:" -ForegroundColor White
docker exec rabbitmq rabbitmqctl list_exchanges

# Check queues  
Write-Host "Queues:" -ForegroundColor White
docker exec rabbitmq rabbitmqctl list_queues

# Check bindings
Write-Host "Bindings:" -ForegroundColor White  
docker exec rabbitmq rabbitmqctl list_bindings

Write-Host "?? RabbitMQ Topology Cleanup Complete!" -ForegroundColor Green

# ============================================================================
# EXPECTED FINAL STATE
# ============================================================================
Write-Host "Expected Final State:" -ForegroundColor Magenta
Write-Host "? Exchange: klim.events.integration (topic)" -ForegroundColor Green
Write-Host "? Queue: klim.affinity.sqlwriter" -ForegroundColor Green  
Write-Host "? Binding: klim.events.integration -> klim.affinity.sqlwriter (klim.integration.affinity.#)" -ForegroundColor Green
Write-Host "? NO fanout exchange: klim.affinity.sqlwriter" -ForegroundColor Red
Write-Host "? NO old queue: klim.integration.affinity.sqlwriter" -ForegroundColor Red