# KLIM Integrations - Docker Deployment Guide

**?? Note**: For complete setup instructions, please see the main [README.md](./README.md) file. This document provides detailed deployment information and troubleshooting.

This document explains how to build and deploy the KLIM Integrations solution using Docker and Docker Compose, with special focus on PowerShell compatibility and direct Docker command usage.

## ?? Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Building Docker Images](#building-docker-images)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [PowerShell Issues and Workarounds](#powershell-issues-and-workarounds)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
- [Troubleshooting](#troubleshooting)
- [Production Considerations](#production-considerations)

## ??? Architecture Overview

The KLIM Integrations solution consists of two main services that connect to existing infrastructure:

### 1. Affinity Integration API (`klim/affinity-integration`)
- **Type**: ASP.NET Core Web API
- **Purpose**: Receives Affinity webhooks and publishes events to RabbitMQ
- **Port**: 8088 (configurable)
- **Base Image**: `mcr.microsoft.com/dotnet/aspnet:8.0`
- **Health Check**: `GET /health`

### 2. Affinity SQL Writer (`klim/affinity-sql-writer`)
- **Type**: .NET Worker Service (Background Service)
- **Purpose**: Consumes RabbitMQ messages and writes data to SQL database
- **Base Image**: `mcr.microsoft.com/dotnet/runtime:8.0`
- **Health Monitoring**: Via application logs

### External Dependencies (Pre-existing)
- **RabbitMQ**: Already deployed separately (`masstransitservices-rabbitmq:latest`)
  - **AMQP Port**: 5672
  - **Management UI**: 15672
  - **Exchange**: `klim.events` (clean naming without environment suffixes)
- **Azure SQL Database**: External database for persistence

## ?? Prerequisites

### System Requirements
- **Docker**: Version 20.10+ (with BuildKit support)
- **Docker Compose**: Version 2.0+
- **Operating System**: Linux, macOS, or Windows with WSL2

### External Dependencies (Already Deployed)
- **RabbitMQ**: Running container with accessible ports
  - Container: `competent_burnell` (masstransitservices-rabbitmq:latest)
  - AMQP: `localhost:5672`
  - Management UI: `http://localhost:15672` (guest/guest)
  - Exchange: `klim.events` preconfigured
- **SQL Server/Azure SQL Database**: For data persistence
- **Network Access**: To external APIs and databases

### Development Tools (Optional)
- **Git**: For version control
- **curl**: For health checks and testing (Linux/macOS) or **PowerShell** (Windows)
- **.NET SDK 8.0**: For local development

## ?? Quick Start

### 1. Clone and Setup
```bash
# Clone the repository
git clone <repository-url>
cd KLIM.Integrations

# Create environment configuration
cp .env.template .env
# Edit .env with your configuration
```

### 2. Configure Environment for External RabbitMQ
Edit `.env` file with your settings:
```bash
# Required: Webhook secret (generate strong random value)
WEBHOOKS__SECRET=your-webhook-secret-here

# Required: Database connection
DATABASE__CONNECTIONSTRING=Server=your-server.database.windows.net;Database=your-db;...
DATABASE__USEAZUREAD=true

# Required: RabbitMQ connection (external instance)
RABBITMQ__HOST=host.docker.internal
RABBITMQ__USERNAME=guest
RABBITMQ__PASSWORD=guest
RABBITMQ__EXCHANGENAME=klim.events
```

### 3. Verify RabbitMQ Connectivity

#### Linux/macOS:
```bash
# Check RabbitMQ is accessible
curl -u guest:guest http://localhost:15672/api/overview

# Verify the exchange exists
curl -u guest:guest http://localhost:15672/api/exchanges/%2F/klim.events
```

#### Windows (PowerShell):
```powershell
# Check RabbitMQ is accessible
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
Invoke-RestMethod -Uri "http://localhost:15672/api/overview" -Headers @{Authorization = "Basic $cred"}

# Verify the exchange exists
Invoke-RestMethod -Uri "http://localhost:15672/api/exchanges/%2F/klim.events" -Headers @{Authorization = "Basic $cred"}
```

#### Alternative (Cross-platform):
```bash
# Test basic connectivity
telnet localhost 5672

# Windows PowerShell
Test-NetConnection -ComputerName localhost -Port 5672
```

### 4. Deploy Integration Services

**Option A: Direct Docker Commands (Recommended for PowerShell Issues)**

```bash
# Build images
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .

# Deploy with Docker Compose
docker-compose up -d
```

**Option B: Using Scripts (if available)**
```bash
# Linux/macOS
./build-docker.sh
./deploy.sh deploy

# Windows (may have issues)
build-docker.bat
deploy.bat
```

#### Verify Deployment (Cross-platform):
```bash
# Linux/macOS
curl http://localhost:8088/health

# Windows PowerShell
Invoke-RestMethod -Uri "http://localhost:8088/health"

# Alternative using docker
docker exec klim-affinity-integration curl -f http://localhost:8088/health
```

### 5. Test Integration Flow

#### Linux/macOS:
```bash
curl -X POST "http://localhost:8088/webhooks/affinity/your-webhook-secret-here" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "organization.created",
    "affinityOrganizationId": 123456,
    "name": "Test Organization",
    "domain": "test.com"
  }'
```

#### Windows PowerShell:
```powershell
$body = @{
    type = "organization.created"
    affinityOrganizationId = 123456
    name = "Test Organization"
    domain = "test.com"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8088/webhooks/affinity/your-webhook-secret-here" `
  -Method POST `
  -ContentType "application/json" `
  -Body $body
```

#### Check Results:
```bash
# Check message in RabbitMQ Management UI (browser)
# Windows: start http://localhost:15672
# macOS: open http://localhost:15672  
# Linux: xdg-open http://localhost:15672
```

## ?? Building Docker Images

### Direct Docker Commands (Recommended)

This approach avoids PowerShell execution issues and works consistently across all platforms:

```bash
# Build Affinity Integration API
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .

# Build Affinity SQL Writer
docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .

# Build with specific version
docker build -t klim/affinity-integration:v1.2.3 -f src/KLIM.Integrations.Affinity/Dockerfile .
docker build -t klim/affinity-sql-writer:v1.2.3 -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .

# View built images
docker images klim/*
```

### Automated Build Scripts

#### Linux/macOS:
```bash
# Build all images with latest tag
./build-docker.sh

# Build with specific version
./build-docker.sh v1.2.3

# Build and push to registry
./build-docker.sh v1.2.3 --push
```

#### Windows:
```batch
REM Build all images with latest tag
build-docker.bat

REM Build with specific version
build-docker.bat v1.2.3

REM Build and push to registry
build-docker.bat v1.2.3 --push
```

### Multi-Platform Builds
```bash
# Build for multiple platforms (requires buildx)
docker buildx create --name multiplatform-builder --use
docker buildx build --platform linux/amd64,linux/arm64 \
  -t klim/affinity-integration:latest \
  -f src/KLIM.Integrations.Affinity/Dockerfile . --push
```

## ?? Configuration

### Environment Variables

#### Application Settings
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `ASPNETCORE_ENVIRONMENT` | Application environment | `Production` | No |
| `VERSION` | Docker image version tag | `latest` | No |
| `AFFINITY_INTEGRATION_PORT` | External port for API | `8088` | No |

#### Webhook Configuration
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `WEBHOOKS__SECRET` | Webhook authentication secret | - | **Yes** |

#### Database Configuration
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `DATABASE__CONNECTIONSTRING` | SQL Server connection string | - | **Yes** |
| `DATABASE__USEAZUREAD` | Use Azure AD authentication | `true` | No |
| `DATABASE__DIAGNOSTICSINTERVALMINUTES` | Diagnostics interval | `5` | No |

#### RabbitMQ Configuration (External Instance)
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `RABBITMQ__HOST` | RabbitMQ server hostname | `host.docker.internal` | **Yes** |
| `RABBITMQ__USERNAME` | RabbitMQ username | `guest` | **Yes** |
| `RABBITMQ__PASSWORD` | RabbitMQ password | `guest` | **Yes** |
| `RABBITMQ__EXCHANGENAME` | Exchange name | `klim.events` | No |
| `RABBITMQ__ROUTINGKEYPREFIX` | Routing key prefix | `klim.integration` | No |

> ?? **Note**: RabbitMQ is deployed separately. The containers connect to the existing RabbitMQ instance at `localhost:5672`.

#### Consumer Configuration
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `CONSUMER__QUEUENAME` | Consumer queue name | `klim.affinity.sqlwriter` | No |
| `CONSUMER__BINDINGKEY` | Message binding pattern | `klim.integration.affinity.#` | No |
| `CONSUMER__PREFETCH` | Message prefetch count | `50` | No |

### Advanced Configuration

#### Network Configuration for External RabbitMQ
Since RabbitMQ runs as a separate container, the integration services use:

```bash
# Docker networking options
# Option 1: Host networking (current configuration)
RABBITMQ__HOST=host.docker.internal

# Option 2: Docker bridge networking (if RabbitMQ is on the same bridge)
RABBITMQ__HOST=rabbitmq-container-name

# Option 3: External host (if RabbitMQ is on different machine)
RABBITMQ__HOST=rabbitmq.company.com
```

#### Logging Levels
```bash
LOGGING__LOGLEVEL__DEFAULT=Information
LOGGING__LOGLEVEL__MICROSOFT=Warning
LOGGING__LOGLEVEL__MASSTRANSIT=Information
```

#### Development Overrides
```bash
# For local development with separate RabbitMQ
ASPNETCORE_ENVIRONMENT=Development
RABBITMQ__HOST=host.docker.internal
LOGGING__LOGLEVEL__DEFAULT=Debug
```

## ?? Deployment

### Production Deployment with External RabbitMQ

#### 1. Prepare Environment
```bash
# Create production environment file
cp .env.template .env.production

# Configure for production with external RabbitMQ
cat > .env.production << EOF
VERSION=v1.0.0
ASPNETCORE_ENVIRONMENT=Production

# External RabbitMQ configuration
RABBITMQ__HOST=host.docker.internal
RABBITMQ__USERNAME=guest
RABBITMQ__PASSWORD=guest
RABBITMQ__EXCHANGENAME=klim.events

# Database and webhook configuration
DATABASE__CONNECTIONSTRING=your-connection-string
WEBHOOKS__SECRET=your-production-secret
EOF
```

#### 2. Deploy Integration Services

**Direct Docker Compose (Recommended):**
```bash
# Deploy with specific environment file
docker-compose --env-file .env.production up -d
```

**Using Deployment Scripts:**
```bash
# Linux/macOS
ENV_FILE=.env.production ./deploy.sh deploy

# Windows (if working)
set ENV_FILE=.env.production
deploy.bat
```

#### 3. Verify Deployment
```bash
# Check integration services are running
docker-compose ps

# Test health endpoints
```

#### Health Check Verification:

**Linux/macOS:**
```bash
curl -f http://localhost:8088/health
```

**Windows PowerShell:**
```powershell
try {
    $response = Invoke-RestMethod -Uri "http://localhost:8088/health"
    Write-Host "Health check passed: $($response.status)" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 10
} catch {
    Write-Host "Health check failed: $_" -ForegroundColor Red
}
```

**Verify RabbitMQ connectivity:**

**Linux/macOS:**
```bash
curl -u guest:guest http://localhost:15672/api/overview
```

**Windows PowerShell:**
```powershell
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
$headers = @{Authorization = "Basic $cred"}
try {
    $response = Invoke-RestMethod -Uri "http://localhost:15672/api/overview" -Headers $headers
    Write-Host "RabbitMQ accessible: $($response.management_version)" -ForegroundColor Green
} catch {
    Write-Host "RabbitMQ connection failed: $_" -ForegroundColor Red
}
```

#### Check logs for connection status:
```bash
docker-compose logs --tail=50
```

### Development Deployment

#### With Existing RabbitMQ
```bash
# Use development configuration
ASPNETCORE_ENVIRONMENT=Development docker-compose up -d
```

## PowerShell Issues and Workarounds

### Common PowerShell Issues

1. **Script Execution Policy**
2. **Batch file execution problems**
3. **Command parsing issues**

### Recommended Workarounds

#### Use Direct Docker Commands Instead of Scripts

**Instead of build-docker.bat:**
```bash
# Build images directly
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .
```

**Instead of deploy.bat:**
```bash
# Deploy directly with Docker Compose
docker-compose up -d
docker-compose ps
docker-compose logs --tail=50
```

#### PowerShell-Specific Commands

**Generate webhook secret:**
```powershell
[System.Web.Security.Membership]::GeneratePassword(64, 16)
```

**Test webhook endpoint:**
```powershell
$body = @{
    type = "organization.created"
    affinityOrganizationId = 123456
    name = "Test Organization"
    domain = "test.com"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8088/webhooks/affinity/your-secret" -Method POST -ContentType "application/json" -Body $body
```

**Check Docker containers:**
```powershell
docker ps | Select-String rabbitmq
```

**View logs:**
```powershell
docker-compose logs --tail=50 | Select-String -Pattern "error|warning" -CaseSensitive:$false
```

## ?? Monitoring and Maintenance

### Health Monitoring

#### Integration Services Health

**Cross-platform health check:**
```bash
# Linux/macOS
curl http://localhost:8088/health

# Windows PowerShell
Invoke-RestMethod -Uri "http://localhost:8088/health" | ConvertTo-Json -Depth 5

# Expected response structure:
{
  "status": "ok",
  "checks": {
    "database": { "status": "healthy", "webhooks": 1234, "lastReceivedAtUtc": "2024-01-15T10:30:00Z" },
    "rabbitmq": { "status": "healthy", "host": "host.docker.internal", "exchange": "klim.events" },
    "bus": { "status": "healthy" },
    "timestampUtc": "2024-01-15T10:35:00Z"
  }
}
```

#### External RabbitMQ Monitoring

**Cross-platform RabbitMQ API calls:**

**Linux/macOS:**
```bash
# Check RabbitMQ status via API
curl -u guest:guest http://localhost:15672/api/overview

# Monitor specific exchange
curl -u guest:guest http://localhost:15672/api/exchanges/%2F/klim.events

# Check queue depth and consumers
curl -u guest:guest http://localhost:15672/api/queues/%2F/klim.affinity.sqlwriter

# Monitor connections from integration services
curl -u guest:guest http://localhost:15672/api/connections
```

**Windows PowerShell:**
```powershell
# Setup credentials for reuse
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
$headers = @{Authorization = "Basic $cred"}

# Check RabbitMQ status via API
Invoke-RestMethod -Uri "http://localhost:15672/api/overview" -Headers $headers

# Monitor specific exchange
Invoke-RestMethod -Uri "http://localhost:15672/api/exchanges/%2F/klim.events" -Headers $headers

# Check queue depth and consumers
Invoke-RestMethod -Uri "http://localhost:15672/api/queues/%2F/klim.affinity.sqlwriter" -Headers $headers

# Monitor connections from integration services
Invoke-RestMethod -Uri "http://localhost:15672/api/connections" -Headers $headers
```

#### Service Logs
```bash
# View integration service logs
docker-compose logs -f --tail=100

# View specific service logs
docker-compose logs -f --tail=100 affinity-integration
docker-compose logs -f --tail=100 affinity-sql-writer

# Check RabbitMQ container logs
docker logs competent_burnell --tail=100
```

#### Resource Monitoring
```bash
# Check integration container resource usage
docker stats klim-affinity-integration klim-affinity-sql-writer

# Include RabbitMQ container monitoring
docker stats klim-affinity-integration klim-affinity-sql-writer competent_burnell

# Check disk usage
docker system df

# Check running processes
docker-compose top
```

### Maintenance Commands

#### Service Management (Integration Services Only)
```bash
# View integration service status
docker-compose ps

# Restart integration services
docker-compose restart

# Stop integration services (RabbitMQ remains running)
docker-compose down

# Update integration services to latest images
docker-compose pull
docker-compose up -d --force-recreate
```

#### RabbitMQ Management
```bash
# RabbitMQ is managed separately, but you can monitor:

# Check RabbitMQ container status
docker ps | grep rabbitmq

# Access RabbitMQ Management UI
# Windows: start http://localhost:15672
# macOS: open http://localhost:15672
# Linux: xdg-open http://localhost:15672

# View RabbitMQ logs
docker logs competent_burnell -f

# Restart RabbitMQ (if needed - impacts all services)
docker restart competent_burnell
```

## ?? Troubleshooting

### Common Issues

#### 1. Health Check Failures

**Test API accessibility (cross-platform):**
```bash
# Linux/macOS
curl -v http://localhost:8088/health

# Windows PowerShell
try {
    Invoke-RestMethod -Uri "http://localhost:8088/health" -Verbose
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $_.Exception.Response | Select-Object StatusCode, StatusDescription
}
```

Common causes:
- Database connection issues
- RabbitMQ connection problems
- Port conflicts

#### 2. Database Connection Issues
```bash
# Check connection string format
echo $DATABASE__CONNECTIONSTRING

# PowerShell
$env:DATABASE__CONNECTIONSTRING

# Test Azure AD authentication
# Ensure container has network access to Azure

# Check logs for authentication errors
docker-compose logs affinity-integration | grep -i "database\|sql\|auth"

# PowerShell equivalent
docker-compose logs affinity-integration | Select-String -Pattern "database|sql|auth" -CaseSensitive:$false
```

#### 3. RabbitMQ Connection Issues (External Instance)

**Test connectivity (cross-platform):**
```bash
# Test basic port connectivity
telnet localhost 5672

# Or using nc (if available)
nc -zv localhost 5672

# PowerShell equivalent
Test-NetConnection -ComputerName localhost -Port 5672
```

**Check RabbitMQ container status:**
```bash
# Verify RabbitMQ container is running
docker ps | grep rabbitmq

# Check RabbitMQ container logs
docker logs competent_burnell --tail=50
```

**Test RabbitMQ API access (cross-platform):**

**Linux/macOS:**
```bash
curl -u guest:guest http://localhost:15672/api/overview
```

**Windows PowerShell:**
```powershell
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
$headers = @{Authorization = "Basic $cred"}
try {
    $response = Invoke-RestMethod -Uri "http://localhost:15672/api/overview" -Headers $headers
    Write-Host "RabbitMQ API accessible" -ForegroundColor Green
    $response.rabbitmq_version
} catch {
    Write-Host "RabbitMQ API failed: $_" -ForegroundColor Red
}
```

**Verify exchange exists:**

**Linux/macOS:**
```bash
curl -u guest:guest http://localhost:15672/api/exchanges/%2F/klim.events
```

**Windows PowerShell:**
```powershell
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
$headers = @{Authorization = "Basic $cred"}
try {
    $exchange = Invoke-RestMethod -Uri "http://localhost:15672/api/exchanges/%2F/klim.events" -Headers $headers
    Write-Host "Exchange 'klim.events' exists: $($exchange.name)" -ForegroundColor Green
} catch {
    Write-Host "Exchange 'klim.events' not found or API error: $_" -ForegroundColor Red
}
```

**Check network connectivity from integration containers:**
```bash
docker exec klim-affinity-integration nc -zv host.docker.internal 5672

# PowerShell - test from within container
docker exec klim-affinity-integration powershell -Command "Test-NetConnection -ComputerName host.docker.internal -Port 5672"
```

#### 4. Message Processing Issues
```bash
# Check SQL Writer logs
docker-compose logs affinity-sql-writer

# Verify queue bindings in RabbitMQ Management UI
# Navigate to http://localhost:15672/#/queues

# Check message flow: webhook ? API ? RabbitMQ ? SQL Writer
# 1. Send test webhook (see examples above)
# 2. Check RabbitMQ messages in management UI
# 3. Monitor SQL Writer logs
# 4. Verify database updates
```

#### 5. PowerShell-Specific curl Issues

If you encounter issues with `curl` in PowerShell, use these alternatives:

```powershell
# Instead of: curl -u guest:guest http://localhost:15672/api/overview
# Use:
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
Invoke-RestMethod -Uri "http://localhost:15672/api/overview" -Headers @{Authorization = "Basic $cred"}

# Instead of: curl -X POST "url" -H "Content-Type: application/json" -d '{"key":"value"}'
# Use:
$body = @{key="value"} | ConvertTo-Json
Invoke-RestMethod -Uri "url" -Method POST -ContentType "application/json" -Body $body

# For file downloads, instead of: curl -o file.txt http://example.com/file.txt
# Use:
Invoke-WebRequest -Uri "http://example.com/file.txt" -OutFile "file.txt"
```

### Cross-Platform Command Reference

#### Health Checks
```bash
# Linux/macOS
curl -f http://localhost:8088/health

# Windows PowerShell  
Invoke-RestMethod -Uri "http://localhost:8088/health"

# Windows Command Prompt (if curl.exe is available)
curl.exe -f http://localhost:8088/health
```

#### RabbitMQ API Calls
```bash
# Linux/macOS
curl -u guest:guest http://localhost:15672/api/overview

# Windows PowerShell
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
Invoke-RestMethod -Uri "http://localhost:15672/api/overview" -Headers @{Authorization = "Basic $cred"}

# Alternative: Use Invoke-WebRequest with credentials
$credential = Get-Credential # Enter guest/guest when prompted
Invoke-WebRequest -Uri "http://localhost:15672/api/overview" -Credential $credential
```

## ?? Production Considerations

### Security

#### Secrets Management
```bash
# Use Docker secrets or external secret management
# Never commit .env files with real secrets

# Example with Docker Swarm secrets:
echo "my-webhook-secret" | docker secret create webhook-secret -
echo "rabbitmq-password" | docker secret create rabbitmq-password -
```

#### Network Security
```yaml
# Use custom networks instead of host networking for production
networks:
  klim-integration:
    driver: bridge
  rabbitmq-network:
    driver: bridge
    # Connect RabbitMQ container to this network
```

#### RabbitMQ Security
```bash
# For production RabbitMQ deployment:
# - Use dedicated RabbitMQ users (not guest)
# - Enable TLS/SSL encryption
# - Configure proper firewall rules
# - Use RabbitMQ clustering for HA
```

#### Container Security
```dockerfile
# In Dockerfiles, run as non-root user
RUN addgroup --system --gid 1001 appgroup
RUN adduser --system --uid 1001 --ingroup appgroup appuser
USER appuser
```

### Scalability

#### Horizontal Scaling
```yaml
# Scale SQL Writer instances (consumers)
docker-compose up -d --scale affinity-sql-writer=3

# Use load balancer for API instances
# Configure RabbitMQ clustering for high availability
```

#### RabbitMQ Clustering
```bash
# For high availability, deploy RabbitMQ cluster
# Configure multiple RabbitMQ nodes
# Use HAProxy or similar for RabbitMQ load balancing
# Update RABBITMQ__HOST to point to load balancer
```

#### Resource Limits
```yaml
# Add resource limits to docker-compose.yml
services:
  affinity-integration:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
```

### High Availability

#### Database
```bash
# Use Azure SQL Database with geo-replication
# Configure connection pooling and retry policies
# Implement circuit breaker patterns
```

#### Message Queue (External RabbitMQ)
```bash
# Deploy RabbitMQ cluster across multiple nodes
# Configure queue mirroring/replication
# Use persistent messages for critical data
# Implement dead letter queues
```

#### Monitoring
```bash
# Integrate with monitoring solutions:
# - Prometheus + Grafana (can monitor both integration services and RabbitMQ)
# - Azure Monitor
# - DataDog, New Relic, etc.

# RabbitMQ monitoring endpoints:
# - http://localhost:15672/api/overview (JSON metrics)
# - Prometheus plugin for RabbitMQ metrics
```

### Backup and Recovery

#### Database Backups
```sql
-- Automated backups in Azure SQL Database
-- Point-in-time recovery available
-- Configure backup retention policies
```

#### RabbitMQ Persistence
```bash
# RabbitMQ data is persisted in Docker volume
# Volume: e0d190d226335788ed8f516ad409b2ffc922948f454db085b070bd32b61ee70e

# Create RabbitMQ configuration backups (cross-platform)
```

**Linux/macOS:**
```bash
curl -u guest:guest http://localhost:15672/api/definitions > rabbitmq-backup.json
```

**Windows PowerShell:**
```powershell
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
$headers = @{Authorization = "Basic $cred"}
$backup = Invoke-RestMethod -Uri "http://localhost:15672/api/definitions" -Headers $headers
$backup | ConvertTo-Json -Depth 10 | Out-File -FilePath "rabbitmq-backup.json" -Encoding UTF8
```

#### Configuration Backups
```bash
# Store backups in secure location
# Version control configuration files
```

### Performance Optimization

#### Image Optimization
```dockerfile
# Multi-stage builds to reduce image size
# Use Alpine-based images where possible
# Optimize layer caching
```

#### Application Performance
```csharp
// Configure connection pooling
// Implement caching strategies
// Use async/await patterns
// Monitor and optimize SQL queries
```

#### RabbitMQ Performance Tuning
```bash
# Configure appropriate prefetch counts
# Monitor queue depths
# Use appropriate queue types (classic vs quorum)
# Configure memory and disk thresholds
```

---

## ?? Additional Resources

- [Main README.md](./README.md) - Complete setup and usage instructions
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)
- [ASP.NET Core in Docker](https://docs.microsoft.com/en-us/aspnet/core/host-and-deploy/docker/)
- [RabbitMQ Management API](https://rabbitmq.com/management.html#http-api)
- [PowerShell Web Cmdlets](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod)
- [KLIM.Events Standards](./KLIM-Events-RabbitMQ-Standards.md)

## ?? License

This project is licensed under the MIT License - see the LICENSE file for details.