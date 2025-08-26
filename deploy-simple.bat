@echo off
REM =============================================================================
REM KLIM Integrations - Simple Windows Deployment (Batch Alternative)
REM =============================================================================
REM This is a simplified deployment script that uses direct Docker commands
REM to avoid PowerShell execution issues.
REM Usage: deploy-simple.bat [action]

setlocal

set ACTION=%1
if "%ACTION%"=="" set ACTION=deploy

echo [INFO] KLIM Integrations Simple Deployment
echo [INFO] Action: %ACTION%

REM Validate Docker
docker --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not installed or not in PATH
    exit /b 1
)

docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker daemon is not running
    exit /b 1
)

REM Check for required files
if not exist "docker-compose.yml" (
    echo [ERROR] docker-compose.yml not found
    exit /b 1
)

if not exist ".env" (
    echo [WARNING] .env file not found
    if exist ".env.template" (
        echo [INFO] Copying .env.template to .env
        copy .env.template .env
        echo [WARNING] Please edit .env with your configuration
        pause
    ) else (
        echo [ERROR] No .env.template found
        exit /b 1
    )
)

goto %ACTION%

:deploy
echo [INFO] Building Docker images...
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
if errorlevel 1 (
    echo [ERROR] Failed to build affinity-integration image
    exit /b 1
)

docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .
if errorlevel 1 (
    echo [ERROR] Failed to build affinity-sql-writer image
    exit /b 1
)

echo [INFO] Starting services with docker-compose...
docker-compose up -d
if errorlevel 1 (
    echo [ERROR] Failed to start services
    exit /b 1
)

echo [INFO] Waiting for services to start...
timeout /t 15 >nul

echo [INFO] Service status:
docker-compose ps

echo [SUCCESS] Deployment completed!
echo [INFO] Health check: http://localhost:8088/health
echo [INFO] RabbitMQ Management: http://localhost:15672
goto end

:stop
echo [INFO] Stopping services...
docker-compose down
echo [SUCCESS] Services stopped
goto end

:logs
echo [INFO] Showing logs...
docker-compose logs --tail=50
goto end

:status
echo [INFO] Service status:
docker-compose ps
echo.
echo [INFO] Docker images:
docker images klim/*
goto end

:build
echo [INFO] Building Docker images only...
docker build -t klim/affinity-integration:latest -f src/KLIM.Integrations.Affinity/Dockerfile .
if errorlevel 1 (
    echo [ERROR] Failed to build affinity-integration image
    exit /b 1
)

docker build -t klim/affinity-sql-writer:latest -f src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile .
if errorlevel 1 (
    echo [ERROR] Failed to build affinity-sql-writer image
    exit /b 1
)

echo [SUCCESS] Images built successfully
docker images klim/*
goto end

:restart
call :stop
call :deploy
goto end

:help
echo Usage: %0 [action]
echo.
echo Actions:
echo   deploy    Build images and deploy services (default)
echo   build     Build Docker images only
echo   stop      Stop services
echo   restart   Restart services
echo   logs      Show service logs
echo   status    Show service status
echo   help      Show this help
echo.
echo Examples:
echo   %0                # Deploy services
echo   %0 build         # Build images only
echo   %0 stop          # Stop services
echo   %0 logs          # Show logs
goto end

:unknown
echo [ERROR] Unknown action: %ACTION%
echo.
call :help
exit /b 1

:end
echo [INFO] Script completed