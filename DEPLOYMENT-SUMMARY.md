# KLIM Integrations - Quick Deployment Summary

This document provides a quick reference for deploying the KLIM Integrations solution with Docker, including workarounds for PowerShell issues.

## ?? Files Overview

### Core Application Files
- `src/KLIM.Integrations.Affinity/` - Web API for receiving webhooks
- `src/KLIM.Integrations.Affinity.SqlWriter/` - Worker service for processing messages
- `src/KLIM.Integrations.Contracts/` - Shared contracts and infrastructure

### Docker Files
- `docker-compose.yml` - Main Docker Compose configuration
- `src/KLIM.Integrations.Affinity/Dockerfile` - API container build
- `src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile` - Worker service container build
- `.dockerignore` - Docker build exclusions

### Deployment Scripts
- `deploy.ps1` - PowerShell-native deployment script (Windows - Recommended)
- `deploy-simple.bat` - Simple batch file alternative
- `build-docker.sh` - Linux/macOS build script
- `deploy.sh` - Linux/macOS deployment script
- `build-docker.bat` - Windows build script (may have issues)

### Configuration
- `.env.template` - Environment variable template
- `.env` - Your configuration (created from template)

### Documentation
- `README.md` - Main documentation
- `DOCKER-DEPLOYMENT.md` - Comprehensive Docker deployment guide
- `POWERSHELL-TROUBLESHOOTING.md` - PowerShell-specific troubleshooting
- `DEPLOYMENT-SUMMARY.md` - This quick reference

## ?? Quick Deployment (Choose One Method)

### Method 1: PowerShell Script (Windows - Recommended)
```powershell
# Setup
cp .env.template .env
# Edit .env with your configuration

# Deploy
.\deploy.ps1 deploy

# Check status
.\deploy.ps1 status
```

### Method 2: Simple Batch File (Windows - If PowerShell Issues)
```cmd
REM Setup
copy .env.template .env
REM Edit .env with your configuration

REM Deploy
deploy-simple.bat deploy

REM Check status
deploy-simple.bat status
```

### Method 3: Direct Docker Commands (Universal - Most Reliable)
```bash
# Setup
cp .env.template .env
# Edit .env with your configuration

# Build
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .

# Deploy
docker-compose up -d

# Check status
docker-compose ps
```

### Method 4: Shell Scripts (Linux/macOS)
```bash
# Setup
cp .env.template .env
# Edit .env with your configuration

# Deploy
./build-docker.sh
./deploy.sh deploy

# Check status
./deploy.sh status
```

## ? Essential Commands

### Health Checks
```bash
# Linux/macOS
curl http://localhost:8088/health

# Windows PowerShell
Invoke-RestMethod -Uri "http://localhost:8088/health"
```

### Service Management
```bash
# View logs
docker-compose logs --tail=50

# Restart services
docker-compose restart

# Stop services
docker-compose down

# Update services
docker-compose pull
docker-compose up -d --force-recreate
```

### RabbitMQ Management
- **Management UI**: http://localhost:15672 (guest/guest)
- **API Endpoint**: http://localhost:15672/api/overview

```bash
# Linux/macOS
curl -u guest:guest http://localhost:15672/api/overview

# Windows PowerShell
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
Invoke-RestMethod -Uri "http://localhost:15672/api/overview" -Headers @{Authorization = "Basic $cred"}
```

## ?? Configuration Quick Reference

### Required Environment Variables (.env file)
```bash
# Webhook Secret (generate strong random value)
WEBHOOKS__SECRET=your-webhook-secret-here

# Database (Azure SQL Database)
DATABASE__CONNECTIONSTRING=Server=your-server.database.windows.net;Database=your-db;...
DATABASE__USEAZUREAD=true

# RabbitMQ (External container)
RABBITMQ__HOST=host.docker.internal
RABBITMQ__USERNAME=guest
RABBITMQ__PASSWORD=guest
RABBITMQ__EXCHANGENAME=klim.events
```

### Generate Webhook Secret
```powershell
# PowerShell
[System.Web.Security.Membership]::GeneratePassword(64, 16)

# Linux/macOS
openssl rand -hex 32
```

## ?? Test Deployment

### 1. Health Check
```bash
# Linux/macOS
curl http://localhost:8088/health

# Windows PowerShell
Invoke-RestMethod -Uri "http://localhost:8088/health"
```

### 2. Send Test Webhook
```powershell
# PowerShell
$body = @{
    type = "organization.created"
    affinityOrganizationId = 123456
    name = "Test Organization"
    domain = "test.com"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8088/webhooks/affinity/your-webhook-secret" `
    -Method POST -ContentType "application/json" -Body $body
```

### 3. Check Results
- Verify health status: `http://localhost:8088/health`
- Check RabbitMQ Management UI: `http://localhost:15672`
- View logs: `docker-compose logs --tail=50`

## ? Common Issues and Solutions

### PowerShell Execution Policy
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Batch File Hanging in PowerShell
**Solution**: Use direct Docker commands (Method 3 above)

### RabbitMQ Connection Issues
```bash
# Test connectivity
Test-NetConnection -ComputerName localhost -Port 5672

# Check RabbitMQ container
docker ps | grep rabbitmq
```

### Docker Build Issues
```bash
# Clear Docker cache
docker builder prune -f

# Check available space
docker system df
```

## ?? Service URLs After Deployment

- **Integration API**: http://localhost:8088
- **Health Check**: http://localhost:8088/health
- **RabbitMQ Management**: http://localhost:15672 (guest/guest)
- **Webhook Endpoint**: http://localhost:8088/webhooks/affinity/{your-secret}

## ??? Architecture Summary

```
[Affinity Webhooks] 
    ? HTTP POST
[Affinity Integration API:8088] 
    ? RabbitMQ Message
[External RabbitMQ:5672] 
    ? Consumer
[Affinity SQL Writer] 
    ? SQL Insert/Update
[Azure SQL Database]
```

## ?? Full Documentation

For comprehensive information, see:
- [README.md](./README.md) - Complete setup and usage
- [DOCKER-DEPLOYMENT.md](./DOCKER-DEPLOYMENT.md) - Detailed Docker deployment
- [POWERSHELL-TROUBLESHOOTING.md](./POWERSHELL-TROUBLESHOOTING.md) - PowerShell issues

---

**Need Help?** Use Method 3 (Direct Docker Commands) - it's the most reliable across all environments.