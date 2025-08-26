# KLIM Integrations

A comprehensive .NET 8 integration solution for processing Affinity CRM webhooks with Docker deployment and RabbitMQ messaging.

## ??? Architecture Overview

The KLIM Integrations solution consists of two main microservices that connect to existing infrastructure:

### 1. Affinity Integration API (`klim/affinity-integration`)
- **Type**: ASP.NET Core Web API (.NET 8)
- **Purpose**: Receives Affinity webhooks and publishes events to RabbitMQ
- **Port**: 8088 (configurable)
- **Health Check**: `GET /health`
- **Features**: 
  - Webhook authentication and validation
  - Event deduplication using SHA-256
  - Structured logging with correlation IDs
  - Comprehensive health monitoring

### 2. Affinity SQL Writer (`klim/affinity-sql-writer`)
- **Type**: .NET Worker Service (Background Service)
- **Purpose**: Consumes RabbitMQ messages and writes data to SQL database
- **Features**:
  - High-throughput message processing
  - Database upsert operations
  - Retry policies and error handling
  - Integration diagnostics

### External Dependencies (Pre-existing)
- **RabbitMQ**: External container (`masstransitservices-rabbitmq:latest`)
  - **AMQP Port**: 5672
  - **Management UI**: 15672 (guest/guest)
  - **Exchange**: `klim.events` (clean naming)
- **Azure SQL Database**: External database for persistence

## ?? Prerequisites

### System Requirements
- **Docker**: Version 20.10+ (with BuildKit support)
- **Docker Compose**: Version 2.0+
- **Operating System**: Linux, macOS, or Windows with WSL2

### External Dependencies (Already Deployed)
- **RabbitMQ**: Running container accessible at `localhost:5672`
  - Container: `competent_burnell` (masstransitservices-rabbitmq:latest)
  - Management UI: `http://localhost:15672` (guest/guest)
  - Exchange: `klim.events` preconfigured
- **SQL Server/Azure SQL Database**: For data persistence

## ?? Quick Start

### 1. Clone and Setup
```bash
# Clone the repository
git clone <repository-url>
cd KLIM.Integrations

# Create environment configuration
cp .env.template .env
# Edit .env with your configuration (see Configuration section below)
```

### 2. Configure Environment
Edit the `.env` file with your settings:

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

### 3. Deploy with Docker

#### Option A: Using PowerShell Script (Windows - Recommended)

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

#### Option B: Using Simple Batch File (Windows Alternative)

```cmd
# Deploy services
deploy-simple.bat deploy

# Build images only
deploy-simple.bat build

# Show status
deploy-simple.bat status
```

#### Option C: Using Direct Docker Commands (Universal - Best for Issues)

**Build Docker Images:**
```bash
# Build Affinity Integration API
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .

# Build Affinity SQL Writer
docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .
```

**Deploy with Docker Compose:**
```bash
# Start the integration services
docker-compose up -d

# Verify deployment
docker-compose ps
```

#### Option D: Using Shell Scripts (Linux/macOS)

```bash
./build-docker.sh
./deploy.sh deploy
```

> **Note**: If you encounter PowerShell execution issues with batch files, use Option C (Direct Docker Commands) or see our [PowerShell Troubleshooting Guide](./POWERSHELL-TROUBLESHOOTING.md).

### 4. Verify Deployment

**Check service health:**
```bash
# Linux/macOS
curl http://localhost:8088/health

# Windows PowerShell
Invoke-RestMethod -Uri "http://localhost:8088/health"
```

**Verify RabbitMQ connectivity:**
```bash
# Linux/macOS
curl -u guest:guest http://localhost:15672/api/overview

# Windows PowerShell
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
Invoke-RestMethod -Uri "http://localhost:15672/api/overview" -Headers @{Authorization = "Basic $cred"}
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

#### Consumer Configuration
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `CONSUMER__QUEUENAME` | Consumer queue name | `klim.affinity.sqlwriter` | No |
| `CONSUMER__BINDINGKEY` | Message binding pattern | `klim.integration.affinity.#` | No |
| `CONSUMER__PREFETCH` | Message prefetch count | `50` | No |

## ?? Building Docker Images

### Direct Docker Commands (Recommended)

```bash
# Build all images
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .

# Build with specific version
docker build -t klim/affinity-integration:v1.2.3 -f src/KLIM.Integrations.Affinity/Dockerfile .
docker build -t klim/affinity-sql-writer:v1.2.3 -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .

# View built images
docker images klim/*
```

### Multi-Platform Builds
```bash
# Build for multiple platforms (requires buildx)
docker buildx create --name multiplatform-builder --use
docker buildx build --platform linux/amd64,linux/arm64 \
  -t klim/affinity-integration:latest \
  -f src/KLIM.Integrations.Affinity/Dockerfile . --push
```

## ?? Deployment

### Production Deployment

#### 1. Prepare Environment
```bash
# Create production environment file
cp .env.template .env.production

# Configure for production
# Edit .env.production with your settings
```

#### 2. Deploy Integration Services
```bash
# Deploy with specific environment file
docker-compose --env-file .env.production up -d

# Verify deployment
docker-compose ps
docker-compose logs --tail=50
```

#### 3. Verify Deployment

**Health Check Verification:**
```bash
# Linux/macOS
curl -f http://localhost:8088/health

# Windows PowerShell
try {
    $response = Invoke-RestMethod -Uri "http://localhost:8088/health"
    Write-Host "Health check passed: $($response.status)" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 10
} catch {
    Write-Host "Health check failed: $_" -ForegroundColor Red
}
```

**Verify RabbitMQ connectivity:**
```bash
# Linux/macOS
curl -u guest:guest http://localhost:15672/api/overview

# Windows PowerShell
$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
$headers = @{Authorization = "Basic $cred"}
try {
    $response = Invoke-RestMethod -Uri "http://localhost:15672/api/overview" -Headers $headers
    Write-Host "RabbitMQ accessible: $($response.management_version)" -ForegroundColor Green
} catch {
    Write-Host "RabbitMQ connection failed: $_" -ForegroundColor Red
}
```

## ?? Monitoring and Maintenance

### Health Monitoring

**Integration Services Health:**
```bash
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

**Service Logs:**
```bash
# View integration service logs
docker-compose logs -f --tail=100

# View specific service logs
docker-compose logs -f --tail=100 affinity-integration
docker-compose logs -f --tail=100 affinity-sql-writer

# Check resource usage
docker stats klim-affinity-integration klim-affinity-sql-writer
```

### Service Management

```bash
# View service status
docker-compose ps

# Restart services
docker-compose restart

# Stop services (RabbitMQ remains running)
docker-compose down

# Update services to latest images
docker-compose pull
docker-compose up -d --force-recreate
```

## ?? Troubleshooting

### Common Issues

#### 1. PowerShell Script Execution Issues

If you encounter issues with PowerShell scripts or batch files:

**Quick Solution**: Use direct Docker commands:
```bash
# Build images directly
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .

# Deploy directly
docker-compose up -d
```

**Detailed Help**: See our [PowerShell Troubleshooting Guide](./POWERSHELL-TROUBLESHOOTING.md).

#### 2. RabbitMQ Connection Issues

**Test connectivity:**
```bash
# Test basic port connectivity
# Linux/macOS
nc -zv localhost 5672

# Windows PowerShell
Test-NetConnection -ComputerName localhost -Port 5672
```

**Check RabbitMQ container:**
```bash
# Verify RabbitMQ container is running
docker ps | grep rabbitmq

# Check RabbitMQ container logs
docker logs competent_burnell --tail=50
```

#### 3. Database Connection Issues

**Check connection string:**
```bash
# View environment variables (be careful with secrets)
docker exec klim-affinity-integration env | grep DATABASE
```

**Check logs for authentication errors:**
```bash
docker-compose logs affinity-integration | grep -i "database\|sql\|auth"
```

#### 4. Health Check Failures

**Test API accessibility:**
```bash
# Linux/macOS
curl -v http://localhost:8088/health

# Windows PowerShell
try {
    Invoke-RestMethod -Uri "http://localhost:8088/health" -Verbose
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
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
```

## ?? Testing

### Test Integration Flow

**Send a test webhook:**

**Linux/macOS:**
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

**Windows PowerShell:**
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

**Check Results:**
1. Verify message in RabbitMQ Management UI: `http://localhost:15672`
2. Check logs: `docker-compose logs --tail=50`
3. Verify database updates

## ?? Production Considerations

### Security
- Use Docker secrets or external secret management
- Never commit `.env` files with real secrets
- Use dedicated RabbitMQ users (not guest)
- Enable TLS/SSL encryption for external connections
- Configure proper firewall rules

### Scalability
- Scale SQL Writer instances: `docker-compose up -d --scale affinity-sql-writer=3`
- Use load balancer for API instances
- Configure RabbitMQ clustering for high availability

### Monitoring
- Integrate with monitoring solutions (Prometheus, Grafana, Azure Monitor)
- Set up alerting for health check failures
- Monitor RabbitMQ queue depths and consumer lag

## ?? Documentation

- **[Docker Deployment Guide](./DOCKER-DEPLOYMENT.md)** - Comprehensive Docker deployment instructions
- **[PowerShell Troubleshooting Guide](./POWERSHELL-TROUBLESHOOTING.md)** - PowerShell-specific issues and solutions
- **[KLIM.Events Standards](./KLIM-Events-RabbitMQ-Standards.md)** - RabbitMQ messaging standards

## ?? Additional Resources

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)
- [ASP.NET Core in Docker](https://docs.microsoft.com/en-us/aspnet/core/host-and-deploy/docker/)
- [RabbitMQ Management API](https://rabbitmq.com/management.html#http-api)

## ?? License

This project is licensed under the MIT License - see the LICENSE file for details.

---

## Quick Command Reference

### Essential Commands (Copy & Paste Ready)

**Build and Deploy (Universal):**
```bash
# Build images
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .

# Deploy
docker-compose up -d

# Check status
docker-compose ps
```

**Health Checks:**
```bash
# Linux/macOS
curl http://localhost:8088/health

# Windows PowerShell
Invoke-RestMethod -Uri "http://localhost:8088/health"
```

**Management:**
```bash
# View logs
docker-compose logs --tail=50

# Stop services
docker-compose down

# Restart services
docker-compose restart