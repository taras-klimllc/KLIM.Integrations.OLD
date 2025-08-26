# =============================================================================
# KLIM Integrations - PowerShell Deployment Script
# =============================================================================
# This script provides PowerShell-native deployment for KLIM Integrations
# Avoids batch file execution issues common in PowerShell environments
# Usage: .\deploy.ps1 [action] [environment]

param(
    [Parameter(Position=0)]
    [ValidateSet("deploy", "stop", "restart", "update", "logs", "status", "test-rabbitmq", "backup", "cleanup", "build", "help")]
    [string]$Action = "deploy",
    
    [Parameter(Position=1)]
    [string]$Environment = "production",
    
    [switch]$Force,
    [switch]$Verbose
)

# Configuration
$ScriptRoot = $PSScriptRoot
$ComposeFile = Join-Path $ScriptRoot "docker-compose.yml"
$EnvFile = Join-Path $ScriptRoot ".env"
$BackupDir = Join-Path $ScriptRoot "backups"

# Colors for output
$Colors = @{
    Info = "Blue"
    Success = "Green" 
    Warning = "Yellow"
    Error = "Red"
}

# Helper functions
function Write-InfoLog {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Info
}

function Write-SuccessLog {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor $Colors.Success
}

function Write-WarningLog {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $Colors.Warning
}

function Write-ErrorLog {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $Colors.Error
}

function Test-Prerequisites {
    Write-InfoLog "Validating deployment prerequisites..."
    
    # Test Docker
    try {
        $null = docker --version
        Write-InfoLog "Docker: OK"
    }
    catch {
        Write-ErrorLog "Docker is not installed or not in PATH"
        return $false
    }
    
    # Test Docker daemon
    try {
        $null = docker info 2>$null
        Write-InfoLog "Docker daemon: OK"
    }
    catch {
        Write-ErrorLog "Docker daemon is not running"
        return $false
    }
    
    # Test Docker Compose
    try {
        $null = docker compose version 2>$null
        Write-InfoLog "Docker Compose: OK"
        $script:ComposeCmd = "docker compose"
    }
    catch {
        try {
            $null = docker-compose --version
            Write-InfoLog "Docker Compose (legacy): OK"
            $script:ComposeCmd = "docker-compose"
        }
        catch {
            Write-ErrorLog "Docker Compose is not available"
            return $false
        }
    }
    
    # Test compose file
    if (-not (Test-Path $ComposeFile)) {
        Write-ErrorLog "Docker Compose file not found: $ComposeFile"
        return $false
    }
    
    # Test environment file
    if (-not (Test-Path $EnvFile)) {
        Write-WarningLog "Environment file not found: $EnvFile"
        $templateFile = Join-Path $ScriptRoot ".env.template"
        if (Test-Path $templateFile) {
            Write-InfoLog "Creating from template..."
            Copy-Item $templateFile $EnvFile
            Write-WarningLog "Please edit $EnvFile with your configuration before deploying"
            return $false
        }
        else {
            Write-ErrorLog "No environment template found"
            return $false
        }
    }
    
    Write-SuccessLog "Prerequisites validated"
    return $true
}

function Test-RabbitMQConnectivity {
    Write-InfoLog "Testing external RabbitMQ connectivity..."
    
    if (-not (Test-Path $EnvFile)) {
        Write-WarningLog "Cannot test RabbitMQ connectivity - no environment file"
        return $false
    }
    
    # Extract RabbitMQ host from .env file
    $envContent = Get-Content $EnvFile -Raw
    $hostMatch = [regex]::Match($envContent, 'RABBITMQ__HOST=(.+)')
    
    if ($hostMatch.Success) {
        $rabbitmqHost = $hostMatch.Groups[1].Value.Trim('"', ' ')
        Write-InfoLog "Testing connection to RabbitMQ host: $rabbitmqHost"
        
        # Test port connectivity
        try {
            $connection = Test-NetConnection -ComputerName $rabbitmqHost -Port 5672 -WarningAction SilentlyContinue
            if ($connection.TcpTestSucceeded) {
                Write-SuccessLog "RabbitMQ port test passed"
                
                # Test management API if possible
                try {
                    $cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
                    $headers = @{Authorization = "Basic $cred"}
                    $response = Invoke-RestMethod -Uri "http://${rabbitmqHost}:15672/api/overview" -Headers $headers -TimeoutSec 5
                    Write-SuccessLog "RabbitMQ management API accessible: $($response.management_version)"
                    return $true
                }
                catch {
                    Write-WarningLog "RabbitMQ port accessible but management API failed: $($_.Exception.Message)"
                    return $true  # Port test passed, which is sufficient
                }
            }
            else {
                Write-WarningLog "Cannot connect to RabbitMQ port 5672 on $rabbitmqHost"
                return $false
            }
        }
        catch {
            Write-WarningLog "RabbitMQ connectivity test failed: $($_.Exception.Message)"
            return $false
        }
    }
    else {
        Write-WarningLog "RABBITMQ__HOST not found in environment file"
        return $false
    }
}

function Build-DockerImages {
    param([string]$Version = "latest")
    
    Write-InfoLog "Building Docker images with version: $Version"
    
    $images = @(
        @{
            Name = "klim/affinity-integration"
            Dockerfile = "src/KLIM.Integrations.Affinity/Dockerfile"
        },
        @{
            Name = "klim/affinity-sql-writer"
            Dockerfile = "src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile"
        }
    )
    
    $failed = @()
    
    foreach ($image in $images) {
        $fullTag = "$($image.Name):$Version"
        Write-InfoLog "Building $fullTag..."
        
        try {
            $buildArgs = @(
                "build",
                "-t", $fullTag,
                "-f", $image.Dockerfile,
                "."
            )
            
            $process = Start-Process -FilePath "docker" -ArgumentList $buildArgs -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -eq 0) {
                Write-SuccessLog "Successfully built $fullTag"
                
                # Tag as latest if version is not latest
                if ($Version -ne "latest") {
                    $latestTag = "$($image.Name):latest"
                    docker tag $fullTag $latestTag
                    Write-InfoLog "Tagged as $latestTag"
                }
            }
            else {
                Write-ErrorLog "Failed to build $fullTag"
                $failed += $fullTag
            }
        }
        catch {
            Write-ErrorLog "Error building $fullTag: $($_.Exception.Message)"
            $failed += $fullTag
        }
    }
    
    if ($failed.Count -eq 0) {
        Write-SuccessLog "All images built successfully!"
        
        # Show built images
        Write-InfoLog "Built images:"
        docker images "klim/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
        
        return $true
    }
    else {
        Write-ErrorLog "Failed to build $($failed.Count) image(s): $($failed -join ', ')"
        return $false
    }
}

function Deploy-Services {
    Write-InfoLog "Deploying KLIM Integrations ($Environment) with external RabbitMQ..."
    
    # Test RabbitMQ connectivity first
    if (-not (Test-RabbitMQConnectivity) -and -not $Force) {
        $response = Read-Host "RabbitMQ connectivity issues detected. Continue anyway? (y/N)"
        if ($response -notmatch '^[Yy]$') {
            Write-ErrorLog "Deployment cancelled due to RabbitMQ connectivity issues"
            return $false
        }
    }
    
    try {
        # Pull latest images
        Write-InfoLog "Pulling latest images..."
        & $ComposeCmd.Split(' ') -f $ComposeFile --env-file $EnvFile pull
        
        # Start services
        Write-InfoLog "Starting integration services..."
        & $ComposeCmd.Split(' ') -f $ComposeFile --env-file $EnvFile up -d
        
        # Wait for services to be healthy
        Write-InfoLog "Waiting for services to be healthy..."
        Start-Sleep -Seconds 15
        
        # Check service status
        Write-InfoLog "Service status:"
        & $ComposeCmd.Split(' ') -f $ComposeFile --env-file $EnvFile ps
        
        # Test health endpoints
        Write-InfoLog "Testing health endpoints..."
        $port = Get-PortFromEnv
        $maxAttempts = 30
        $attempt = 1
        
        while ($attempt -le $maxAttempts) {
            try {
                $response = Invoke-RestMethod -Uri "http://localhost:$port/health" -TimeoutSec 5
                Write-SuccessLog "Affinity Integration service is healthy"
                break
            }
            catch {
                if ($attempt -eq $maxAttempts) {
                    Write-ErrorLog "Affinity Integration service failed health check after $maxAttempts attempts"
                    Show-Logs
                    return $false
                }
                
                Write-InfoLog "Attempt $attempt/$maxAttempts`: Waiting for health check..."
                Start-Sleep -Seconds 5
                $attempt++
            }
        }
        
        # Show RabbitMQ connection status in health check
        Write-InfoLog "Checking RabbitMQ integration status..."
        try {
            $healthResponse = Invoke-RestMethod -Uri "http://localhost:$port/health" -TimeoutSec 5
            Write-InfoLog "Health check response:"
            $healthResponse | ConvertTo-Json -Depth 10
        }
        catch {
            Write-WarningLog "Could not retrieve detailed health check response"
        }
        
        Write-SuccessLog "Deployment completed successfully!"
        
        # Show service URLs
        Write-Host ""
        Write-InfoLog "Service URLs:"
        Write-Host "  • Affinity Integration API: http://localhost:$port"
        Write-Host "  • Health Check: http://localhost:$port/health"
        Write-Host "  • External RabbitMQ Management: http://localhost:15672 (guest/guest)"
        
        # Show management commands
        Write-Host ""
        Write-InfoLog "Management commands:"
        Write-Host "  • View logs: .\deploy.ps1 logs"
        Write-Host "  • Stop services: .\deploy.ps1 stop"
        Write-Host "  • Restart services: .\deploy.ps1 restart"
        Write-Host "  • Update services: .\deploy.ps1 update"
        Write-Host "  • Test RabbitMQ: .\deploy.ps1 test-rabbitmq"
        
        return $true
    }
    catch {
        Write-ErrorLog "Deployment failed: $($_.Exception.Message)"
        return $false
    }
}

function Stop-Services {
    Write-InfoLog "Stopping KLIM Integrations services (RabbitMQ remains running)..."
    try {
        & $ComposeCmd.Split(' ') -f $ComposeFile --env-file $EnvFile down
        Write-SuccessLog "Integration services stopped"
        Write-InfoLog "Note: External RabbitMQ container remains running"
        return $true
    }
    catch {
        Write-ErrorLog "Failed to stop services: $($_.Exception.Message)"
        return $false
    }
}

function Restart-Services {
    Write-InfoLog "Restarting KLIM Integrations services..."
    if (Stop-Services) {
        return Deploy-Services
    }
    return $false
}

function Update-Services {
    Write-InfoLog "Updating KLIM Integrations services..."
    
    try {
        # Create backup
        Backup-Configuration
        
        # Pull latest images
        Write-InfoLog "Pulling latest images..."
        & $ComposeCmd.Split(' ') -f $ComposeFile --env-file $EnvFile pull
        
        # Recreate and restart services
        Write-InfoLog "Recreating services with latest images..."
        & $ComposeCmd.Split(' ') -f $ComposeFile --env-file $EnvFile up -d --force-recreate
        
        Write-SuccessLog "Services updated successfully"
        return $true
    }
    catch {
        Write-ErrorLog "Update failed: $($_.Exception.Message)"
        return $false
    }
}

function Show-Logs {
    param([string]$Service = "")
    
    try {
        if ($Service) {
            Write-InfoLog "Showing logs for $Service..."
            & $ComposeCmd.Split(' ') -f $ComposeFile --env-file $EnvFile logs -f --tail 100 $Service
        }
        else {
            Write-InfoLog "Showing logs for all integration services..."
            & $ComposeCmd.Split(' ') -f $ComposeFile --env-file $EnvFile logs -f --tail 100
        }
    }
    catch {
        Write-ErrorLog "Failed to show logs: $($_.Exception.Message)"
    }
}

function Show-Status {
    Write-InfoLog "Integration service status:"
    try {
        & $ComposeCmd.Split(' ') -f $ComposeFile --env-file $EnvFile ps
        
        Write-Host ""
        Write-InfoLog "External RabbitMQ container status:"
        $rabbitmqContainers = docker ps --filter "name=competent_burnell" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
        if ($rabbitmqContainers -and $rabbitmqContainers.Count -gt 1) {
            $rabbitmqContainers
            Write-Host "RabbitMQ container is running"
        }
        else {
            Write-WarningLog "External RabbitMQ container 'competent_burnell' not found"
        }
        
        Write-Host ""
        Write-InfoLog "Docker images:"
        docker images "klim/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    }
    catch {
        Write-ErrorLog "Failed to show status: $($_.Exception.Message)"
    }
}

function Test-RabbitMQ {
    Write-InfoLog "Running RabbitMQ connectivity test..."
    
    # Extract host from .env file
    $rabbitmqHost = "localhost"
    if (Test-Path $EnvFile) {
        $envContent = Get-Content $EnvFile -Raw
        $hostMatch = [regex]::Match($envContent, 'RABBITMQ__HOST=(.+)')
        if ($hostMatch.Success) {
            $rabbitmqHost = $hostMatch.Groups[1].Value.Trim('"', ' ')
        }
    }
    
    Write-InfoLog "Testing RabbitMQ host: $rabbitmqHost"
    
    # Test port connectivity
    $portTest = Test-NetConnection -ComputerName $rabbitmqHost -Port 5672 -WarningAction SilentlyContinue
    if ($portTest.TcpTestSucceeded) {
        Write-SuccessLog "AMQP port (5672) is accessible"
    }
    else {
        Write-ErrorLog "AMQP port (5672) is not accessible"
        return
    }
    
    # Test management API
    try {
        $cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("guest:guest"))
        $headers = @{Authorization = "Basic $cred"}
        $response = Invoke-RestMethod -Uri "http://${rabbitmqHost}:15672/api/overview" -Headers $headers -TimeoutSec 10
        Write-SuccessLog "RabbitMQ Management API accessible"
        Write-InfoLog "RabbitMQ Version: $($response.rabbitmq_version)"
        Write-InfoLog "Management Version: $($response.management_version)"
        
        # Test exchange
        try {
            $exchange = Invoke-RestMethod -Uri "http://${rabbitmqHost}:15672/api/exchanges/%2F/klim.events" -Headers $headers -TimeoutSec 5
            Write-SuccessLog "Exchange 'klim.events' exists"
        }
        catch {
            Write-WarningLog "Exchange 'klim.events' not found or not accessible"
        }
        
        # Show connections
        try {
            $connections = Invoke-RestMethod -Uri "http://${rabbitmqHost}:15672/api/connections" -Headers $headers -TimeoutSec 5
            Write-InfoLog "Active connections: $($connections.Count)"
        }
        catch {
            Write-WarningLog "Could not retrieve connection information"
        }
        
    }
    catch {
        Write-ErrorLog "RabbitMQ Management API failed: $($_.Exception.Message)"
        Write-InfoLog "Management UI should be accessible at: http://${rabbitmqHost}:15672"
    }
}

function Backup-Configuration {
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    
    $backupName = "config-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $backupPath = Join-Path $BackupDir $backupName
    
    Write-InfoLog "Creating configuration backup: $backupName"
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    
    # Backup environment file
    if (Test-Path $EnvFile) {
        Copy-Item $EnvFile (Join-Path $backupPath ".env")
    }
    
    # Backup compose file
    Copy-Item $ComposeFile (Join-Path $backupPath "docker-compose.yml")
    
    Write-SuccessLog "Configuration backed up to $backupPath"
}

function Invoke-Cleanup {
    Write-InfoLog "Cleaning up old Docker resources (integration services only)..."
    
    try {
        # Remove stopped containers
        docker container prune -f
        
        # Remove unused images (be careful with external RabbitMQ)
        docker image prune -f
        
        # Remove unused networks
        docker network prune -f
        
        Write-SuccessLog "Cleanup completed"
        Write-WarningLog "External RabbitMQ resources were not affected"
    }
    catch {
        Write-ErrorLog "Cleanup failed: $($_.Exception.Message)"
    }
}

function Get-PortFromEnv {
    if (Test-Path $EnvFile) {
        $envContent = Get-Content $EnvFile -Raw
        $portMatch = [regex]::Match($envContent, 'AFFINITY_INTEGRATION_PORT=(\d+)')
        if ($portMatch.Success) {
            return $portMatch.Groups[1].Value
        }
    }
    return "8088"  # Default port
}

function Show-Help {
    Write-Host @"
KLIM Integrations - PowerShell Deployment Script

Usage: .\deploy.ps1 [action] [environment] [options]

Actions:
  deploy       Deploy integration services (default)
  build        Build Docker images
  stop         Stop integration services
  restart      Restart integration services
  update       Update services with latest images
  logs         Show service logs
  status       Show service status
  test-rabbitmq Test external RabbitMQ connectivity
  backup       Backup current configuration
  cleanup      Clean up old Docker resources
  help         Show this help message

Options:
  -Force       Skip confirmation prompts
  -Verbose     Show verbose output

Examples:
  .\deploy.ps1                           # Deploy all integration services
  .\deploy.ps1 build                     # Build Docker images
  .\deploy.ps1 logs                      # Show logs for all services
  .\deploy.ps1 test-rabbitmq             # Test external RabbitMQ connectivity
  .\deploy.ps1 deploy -Force             # Deploy without confirmation prompts

Note: This deployment connects to external RabbitMQ (competent_burnell container)
      RabbitMQ is not managed by this deployment script
"@
}

# Main execution
try {
    switch ($Action.ToLower()) {
        "deploy" {
            if (Test-Prerequisites) {
                Deploy-Services | Out-Null
            }
        }
        "build" {
            if (Test-Prerequisites) {
                Build-DockerImages | Out-Null
            }
        }
        "stop" {
            Stop-Services | Out-Null
        }
        "restart" {
            if (Test-Prerequisites) {
                Restart-Services | Out-Null
            }
        }
        "update" {
            if (Test-Prerequisites) {
                Update-Services | Out-Null
            }
        }
        "logs" {
            Show-Logs $Environment
        }
        "status" {
            Show-Status
        }
        "test-rabbitmq" {
            Test-RabbitMQ
        }
        "backup" {
            Backup-Configuration
        }
        "cleanup" {
            Invoke-Cleanup
        }
        "help" {
            Show-Help
        }
        default {
            Write-ErrorLog "Unknown action: $Action"
            Write-Host ""
            Show-Help
            exit 1
        }
    }
}
catch {
    Write-ErrorLog "Script execution failed: $($_.Exception.Message)"
    if ($Verbose) {
        Write-ErrorLog "Stack trace: $($_.ScriptStackTrace)"
    }
    exit 1
}