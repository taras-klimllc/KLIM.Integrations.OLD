# =============================================================================
# KLIM Integrations - RabbitMQ Connectivity Test Script (PowerShell)
# =============================================================================
# Tests connectivity to external RabbitMQ instance using PowerShell
# Usage: .\test-rabbitmq.ps1 [-Host localhost] [-Port 5672]

param(
    [string]$Host = "localhost",
    [int]$Port = 5672,
    [int]$MgmtPort = 15672,
    [string]$Username = "guest",
    [string]$Password = "guest",
    [switch]$Help
)

# Show help and exit
if ($Help) {
    Write-Host "KLIM Integrations - RabbitMQ Connectivity Test (PowerShell)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\test-rabbitmq.ps1 [-Host <hostname>] [-Port <port>] [-Help]" -ForegroundColor White
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  -Host      RabbitMQ hostname (default: localhost)" -ForegroundColor White
    Write-Host "  -Port      RabbitMQ AMQP port (default: 5672)" -ForegroundColor White
    Write-Host "  -MgmtPort  RabbitMQ Management port (default: 15672)" -ForegroundColor White
    Write-Host "  -Username  RabbitMQ username (default: guest)" -ForegroundColor White
    Write-Host "  -Password  RabbitMQ password (default: guest)" -ForegroundColor White
    Write-Host "  -Help      Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\test-rabbitmq.ps1" -ForegroundColor White
    Write-Host "  .\test-rabbitmq.ps1 -Host host.docker.internal" -ForegroundColor White
    Write-Host "  .\test-rabbitmq.ps1 -Host 172.17.0.2 -Port 5672" -ForegroundColor White
    exit 0
}

# Helper functions for colored output
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-AmqpConnection {
    Write-Info "Testing AMQP connection to ${Host}:${Port}..."
    
    try {
        $connection = Test-NetConnection -ComputerName $Host -Port $Port -WarningAction SilentlyContinue
        if ($connection.TcpTestSucceeded) {
            Write-Success "AMQP port $Port is accessible"
            return $true
        } else {
            Write-Error "AMQP port $Port is not accessible"
            return $false
        }
    } catch {
        Write-Error "Failed to test AMQP connection: $($_.Exception.Message)"
        return $false
    }
}

function Test-ManagementApi {
    Write-Info "Testing RabbitMQ Management API at http://${Host}:${MgmtPort}..."
    
    try {
        # Create Basic Authentication header
        $credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("${Username}:${Password}"))
        $headers = @{
            Authorization = "Basic $credentials"
        }
        
        $response = Invoke-RestMethod -Uri "http://${Host}:${MgmtPort}/api/overview" -Headers $headers -TimeoutSec 10
        
        if ($response) {
            Write-Success "Management API is accessible and authenticated"
            Write-Info "RabbitMQ Version: $($response.rabbitmq_version)"
            Write-Info "Management Version: $($response.management_version)"
            return $true
        } else {
            Write-Error "Management API returned empty response"
            return $false
        }
    } catch {
        Write-Error "Failed to connect to Management API: $($_.Exception.Message)"
        return $false
    }
}

function Test-ExchangeExists {
    param([string]$ExchangeName = "klim.events")
    
    Write-Info "Checking if exchange '$ExchangeName' exists..."
    
    try {
        # Create Basic Authentication header
        $credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("${Username}:${Password}"))
        $headers = @{
            Authorization = "Basic $credentials"
        }
        
        $response = Invoke-RestMethod -Uri "http://${Host}:${MgmtPort}/api/exchanges/%2F/${ExchangeName}" -Headers $headers -TimeoutSec 10
        
        if ($response -and $response.name -eq $ExchangeName) {
            Write-Success "Exchange '$ExchangeName' exists"
            Write-Info "Exchange Type: $($response.type)"
            Write-Info "Durable: $($response.durable)"
            return $true
        } else {
            Write-Warning "Exchange '$ExchangeName' not found or unexpected response"
            return $false
        }
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Warning "Exchange '$ExchangeName' does not exist (404 Not Found)"
        } else {
            Write-Error "Error checking exchange: $($_.Exception.Message)"
        }
        return $false
    }
}

function Test-DockerConnectivity {
    Write-Info "Testing Docker-specific connectivity options..."
    
    # Test host.docker.internal (Docker Desktop)
    if ($Host -ne "host.docker.internal") {
        Write-Info "Testing host.docker.internal fallback..."
        try {
            $connection = Test-NetConnection -ComputerName "host.docker.internal" -Port $Port -WarningAction SilentlyContinue
            if ($connection.TcpTestSucceeded) {
                Write-Success "host.docker.internal:$Port is accessible"
            } else {
                Write-Warning "host.docker.internal:$Port is not accessible"
            }
        } catch {
            Write-Warning "Could not test host.docker.internal: $($_.Exception.Message)"
        }
    }
    
    # Test localhost fallback
    if ($Host -ne "localhost") {
        Write-Info "Testing localhost fallback..."
        try {
            $connection = Test-NetConnection -ComputerName "localhost" -Port $Port -WarningAction SilentlyContinue
            if ($connection.TcpTestSucceeded) {
                Write-Success "localhost:$Port is accessible"
            } else {
                Write-Warning "localhost:$Port is not accessible"
            }
        } catch {
            Write-Warning "Could not test localhost: $($_.Exception.Message)"
        }
    }
}

function Show-ContainerInfo {
    Write-Info "Checking for RabbitMQ containers..."
    
    try {
        # Check if Docker is available
        $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
        if (-not $dockerVersion) {
            Write-Warning "Docker not available for container inspection"
            return
        }
        
        # Check for RabbitMQ containers
        $containers = docker ps --filter "ancestor=*rabbitmq*" --format "table {{.Names}}`t{{.Image}}`t{{.Ports}}`t{{.Status}}" 2>$null
        if ($containers -and $containers.Count -gt 1) {
            Write-Host $containers
        } else {
            Write-Info "No RabbitMQ containers found with 'docker ps'"
        }
        
        # Check for the specific container mentioned
        $containerExists = docker inspect competent_burnell --format "{{.Name}}" 2>$null
        if ($containerExists) {
            $containerIp = docker inspect competent_burnell --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" 2>$null
            if ($containerIp) {
                Write-Info "Found RabbitMQ container 'competent_burnell' at IP: $containerIp"
                
                # Test direct container IP
                Write-Info "Testing direct container IP connectivity..."
                try {
                    $connection = Test-NetConnection -ComputerName $containerIp -Port $Port -WarningAction SilentlyContinue
                    if ($connection.TcpTestSucceeded) {
                        Write-Success "Direct container IP ${containerIp}:$Port is accessible"
                    } else {
                        Write-Warning "Direct container IP ${containerIp}:$Port is not accessible"
                    }
                } catch {
                    Write-Warning "Could not test container IP: $($_.Exception.Message)"
                }
            }
        }
    } catch {
        Write-Warning "Error inspecting Docker containers: $($_.Exception.Message)"
    }
}

function Show-BashEquivalents {
    Write-Info "Bash/Linux equivalents for cross-platform reference:"
    Write-Host ""
    Write-Host "# Test AMQP port connectivity:" -ForegroundColor Yellow
    Write-Host "nc -zv $Host $Port" -ForegroundColor White
    Write-Host "# or"
    Write-Host "telnet $Host $Port" -ForegroundColor White
    Write-Host ""
    Write-Host "# Test RabbitMQ Management API:" -ForegroundColor Yellow
    Write-Host "curl -u ${Username}:${Password} http://${Host}:${MgmtPort}/api/overview" -ForegroundColor White
    Write-Host ""
    Write-Host "# Check if exchange exists:" -ForegroundColor Yellow
    Write-Host "curl -u ${Username}:${Password} http://${Host}:${MgmtPort}/api/exchanges/%2F/klim.events" -ForegroundColor White
    Write-Host ""
    Write-Host "# Test health endpoint:" -ForegroundColor Yellow
    Write-Host "curl http://localhost:8088/health" -ForegroundColor White
    Write-Host ""
}

function Test-HealthEndpoint {
    Write-Info "Testing KLIM Integration health endpoint..."
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8088/health" -TimeoutSec 10
        
        if ($response -and $response.status) {
            Write-Success "Health endpoint accessible, status: $($response.status)"
            
            # Show health check details
            if ($response.checks) {
                Write-Info "Health check details:"
                if ($response.checks.database) {
                    Write-Host "  Database: $($response.checks.database.status)" -ForegroundColor $(if ($response.checks.database.status -eq "healthy") { "Green" } else { "Red" })
                }
                if ($response.checks.rabbitmq) {
                    Write-Host "  RabbitMQ: $($response.checks.rabbitmq.status)" -ForegroundColor $(if ($response.checks.rabbitmq.status -eq "healthy") { "Green" } else { "Red" })
                }
                if ($response.checks.bus) {
                    Write-Host "  Message Bus: $($response.checks.bus.status)" -ForegroundColor $(if ($response.checks.bus.status -eq "healthy") { "Green" } else { "Red" })
                }
            }
            return $true
        } else {
            Write-Error "Health endpoint returned unexpected response"
            return $false
        }
    } catch {
        Write-Warning "Health endpoint not accessible (integration services may not be running): $($_.Exception.Message)"
        return $false
    }
}

# Main execution
function Main {
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "KLIM Integrations - RabbitMQ Connectivity Test (PowerShell)" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "Testing RabbitMQ connectivity to: ${Host}:${Port}" -ForegroundColor White
    Write-Host ""
    
    $testsPassedCount = 0
    $totalTests = 0
    
    # Test 1: AMQP Connection
    $totalTests++
    if (Test-AmqpConnection) {
        $testsPassedCount++
    }
    Write-Host ""
    
    # Test 2: Management API
    $totalTests++
    if (Test-ManagementApi) {
        $testsPassedCount++
    }
    Write-Host ""
    
    # Test 3: Exchange Existence
    $totalTests++
    if (Test-ExchangeExists) {
        $testsPassedCount++
    }
    Write-Host ""
    
    # Test 4: Health Endpoint (bonus test)
    $totalTests++
    if (Test-HealthEndpoint) {
        $testsPassedCount++
    }
    Write-Host ""
    
    # Additional Docker-specific tests
    Test-DockerConnectivity
    Write-Host ""
    
    # Container information
    Show-ContainerInfo
    Write-Host ""
    
    # Bash equivalents for cross-platform reference
    Show-BashEquivalents
    Write-Host ""
    
    # Summary
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "Test Summary: $testsPassedCount/$totalTests tests passed" -ForegroundColor White
    
    if ($testsPassedCount -eq $totalTests) {
        Write-Success "All connectivity tests passed! RabbitMQ is ready for KLIM Integrations."
        $exitCode = 0
    } elseif ($testsPassedCount -gt 0) {
        Write-Warning "Some tests passed. RabbitMQ may be partially accessible."
        $exitCode = 0
    } else {
        Write-Error "All tests failed. Check RabbitMQ configuration and network connectivity."
        Write-Host ""
        Write-Info "Troubleshooting tips:"
        Write-Host "1. Ensure RabbitMQ container is running: docker ps | Select-String rabbitmq" -ForegroundColor White
        Write-Host "2. Check Docker Desktop is running (Windows/Mac)" -ForegroundColor White
        Write-Host "3. Verify firewall settings allow connections to ports $Port and $MgmtPort" -ForegroundColor White
        Write-Host "4. Try alternative hosts: localhost, host.docker.internal, or container IP" -ForegroundColor White
        $exitCode = 1
    }
    
    Write-Host ""
    Write-Host "Recommended .env configuration:" -ForegroundColor Yellow
    Write-Host "RABBITMQ__HOST=$Host" -ForegroundColor White
    Write-Host "RABBITMQ__USERNAME=$Username" -ForegroundColor White
    Write-Host "RABBITMQ__PASSWORD=$Password" -ForegroundColor White
    Write-Host "RABBITMQ__EXCHANGENAME=klim.events" -ForegroundColor White
    Write-Host ""
    
    exit $exitCode
}

# Execute main function
Main