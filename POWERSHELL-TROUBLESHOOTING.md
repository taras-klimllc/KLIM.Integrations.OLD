# PowerShell and Docker Troubleshooting Guide

This guide addresses common PowerShell execution issues and provides workarounds for Docker deployment of KLIM Integrations.

## ?? Common PowerShell Issues

### 1. Script Execution Policy Issues

**Problem**: PowerShell scripts cannot execute due to execution policy restrictions.

**Error Messages**:
```
deploy.ps1 cannot be loaded because running scripts is disabled on this system
```

**Solution**:
```powershell
# Check current execution policy
Get-ExecutionPolicy

# Set execution policy for current user (recommended)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or bypass for single script execution
PowerShell -ExecutionPolicy Bypass -File .\deploy.ps1 deploy
```

### 2. Batch File Execution Issues

**Problem**: Batch files hang or produce garbled output in PowerShell.

**Symptoms**:
- Scripts appear to run but produce no output
- Infinite loops or hanging processes
- Character encoding issues

**Solution**: Use direct Docker commands instead:

```powershell
# Instead of build-docker.bat
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .

# Instead of deploy.bat
docker-compose up -d
```

### 3. Command Parsing Issues

**Problem**: PowerShell misinterprets command arguments or special characters.

**Solution**: Use explicit argument separation:
```powershell
# Problematic
docker build -t klim/app:latest -f path/Dockerfile .

# Better
docker build -t "klim/app:latest" -f "path/Dockerfile" "."

# Best (using arrays)
$buildArgs = @("build", "-t", "klim/app:latest", "-f", "path/Dockerfile", ".")
& docker $buildArgs
```

## ?? Deployment Workarounds

### Option 1: Use PowerShell Native Script

Use the provided `deploy.ps1` script which is written specifically for PowerShell:

```powershell
# Deploy services
.\deploy.ps1 deploy

# Build images only
.\deploy.ps1 build

# Show status
.\deploy.ps1 status

# Test RabbitMQ connectivity
.\deploy.ps1 test-rabbitmq
```

### Option 2: Use Simple Batch File

Use the simplified `deploy-simple.bat` which avoids complex scripting:

```cmd
# Deploy services
deploy-simple.bat deploy

# Build images only
deploy-simple.bat build

# Show status
deploy-simple.bat status
```

### Option 3: Direct Docker Commands

Execute Docker commands directly in PowerShell:

```powershell
# Build images
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .

# Deploy with compose
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs --tail=50

# Stop services
docker-compose down
```

## ?? Diagnostic Commands

### Check Docker Environment

```powershell
# Verify Docker installation
docker --version
docker compose version

# Check Docker daemon status
docker info

# List running containers
docker ps

# List images
docker images klim/*
```

### Test Network Connectivity

```powershell
# Test RabbitMQ port
Test-NetConnection -ComputerName localhost -Port 5672

# Test RabbitMQ management interface
Test-NetConnection -ComputerName localhost -Port 15672

# Test API port
Test-NetConnection -ComputerName localhost -Port 8088
```

### PowerShell-Specific Commands

```powershell
# Test RabbitMQ API with proper authentication
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
$headers = @{Authorization = "Basic $cred"}
Invoke-RestMethod -Uri "http://localhost:15672/api/overview" -Headers $headers

# Test health endpoint
Invoke-RestMethod -Uri "http://localhost:8088/health"

# Send test webhook
$body = @{
    type = "organization.created"
    affinityOrganizationId = 123456
    name = "Test Organization"
    domain = "test.com"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8088/webhooks/affinity/your-secret" `
    -Method POST -ContentType "application/json" -Body $body
```

## ??? Advanced Troubleshooting

### Docker Build Issues

**Problem**: Docker build fails in PowerShell but works in Command Prompt.

**Diagnosis**:
```powershell
# Check Docker context
docker context ls

# Verify BuildKit
docker buildx ls

# Check available space
docker system df
```

**Solutions**:
```powershell
# Use legacy build (if BuildKit causes issues)
$env:DOCKER_BUILDKIT = "0"
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .

# Clear Docker cache if needed
docker builder prune -f

# Use different builder
docker buildx create --name powershell-builder --use
```

### Docker Compose Issues

**Problem**: Docker Compose commands fail or behave differently in PowerShell.

**Diagnosis**:
```powershell
# Check compose version
docker compose version

# Validate compose file
docker compose -f docker-compose.yml config

# Check environment variables
Get-Content .env
```

**Solutions**:
```powershell
# Use explicit file paths
docker compose -f "$(Get-Location)/docker-compose.yml" --env-file "$(Get-Location)/.env" up -d

# Use full paths if relative paths cause issues
$composeFile = Resolve-Path "docker-compose.yml"
$envFile = Resolve-Path ".env"
docker compose -f $composeFile --env-file $envFile up -d
```

### Environment Variable Issues

**Problem**: Environment variables not loading correctly from `.env` file.

**Diagnosis**:
```powershell
# Check file encoding
Get-Content .env -Encoding UTF8 | Select-Object -First 5

# Verify variable format
Select-String -Path .env -Pattern "^[A-Z].*="
```

**Solutions**:
```powershell
# Ensure proper encoding when creating .env
Get-Content .env.template | Out-File -FilePath .env -Encoding UTF8

# Load variables manually if needed
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#].*)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}
```

## ?? Best Practices for PowerShell + Docker

### 1. Use Explicit Paths
```powershell
# Good
$dockerfile = Join-Path $PWD "src/KLIM.Integrations.Affinity/Dockerfile"
docker build -t klim/affinity-integration:latest -f $dockerfile .

# Better
Push-Location $PSScriptRoot
docker build -t klim/affinity-integration:latest -f "src/KLIM.Integrations.Affinity/Dockerfile" "."
Pop-Location
```

### 2. Handle Errors Properly
```powershell
try {
    docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed with exit code $LASTEXITCODE"
    }
    Write-Host "Build successful" -ForegroundColor Green
}
catch {
    Write-Error "Build failed: $_"
    exit 1
}
```

### 3. Use Arrays for Complex Commands
```powershell
$buildArgs = @(
    "build",
    "-t", "klim/affinity-integration:latest",
    "-f", "src/KLIM.Integrations.Affinity/Dockerfile",
    "."
)
& docker $buildArgs
```

### 4. Validate Prerequisites
```powershell
function Test-DockerAvailable {
    try {
        docker --version | Out-Null
        docker info | Out-Null
        return $true
    }
    catch {
        Write-Error "Docker is not available: $_"
        return $false
    }
}

if (-not (Test-DockerAvailable)) {
    exit 1
}
```

## ?? Quick Reference Commands

### Essential Deployment Commands (PowerShell-Safe)

```powershell
# Complete deployment (one-liner)
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .; docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .; docker-compose up -d

# Check everything is running
docker-compose ps; docker-compose logs --tail=20

# Quick health check
Invoke-RestMethod -Uri "http://localhost:8088/health" | ConvertTo-Json -Depth 5

# Stop everything
docker-compose down
```

### Emergency Recovery

```powershell
# Stop all containers
docker stop $(docker ps -aq)

# Remove all containers (caution!)
docker rm $(docker ps -aq)

# Clean up images (caution!)
docker rmi $(docker images "klim/*" -q)

# Start fresh
docker system prune -f
```

## ?? Additional Resources

- [PowerShell Execution Policies](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
- [Docker for Windows](https://docs.docker.com/desktop/windows/)
- [Docker Compose CLI](https://docs.docker.com/compose/reference/)
- [PowerShell Docker Module](https://www.powershellgallery.com/packages/Docker)

---

**Pro Tip**: When in doubt, use the direct Docker commands shown above. They're the most reliable approach across all environments.