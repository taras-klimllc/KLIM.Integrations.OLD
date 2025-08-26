@echo off
REM =============================================================================
REM KLIM Integrations - Docker Build Script (Windows)
REM =============================================================================
REM This script builds all Docker images for the KLIM Integrations solution
REM Usage: build-docker.bat [version] [--push]

setlocal EnableDelayedExpansion

REM Configuration
set "SOLUTION_NAME=KLIM.Integrations"
set "REGISTRY_PREFIX=klim"
set "VERSION=%~1"
set "PUSH_IMAGES=%~2"

if "%VERSION%"=="" set "VERSION=latest"

REM Helper function to log messages
:log_info
echo [INFO] %~1
goto :eof

:log_success
echo [SUCCESS] %~1
goto :eof

:log_error
echo [ERROR] %~1
goto :eof

REM Validate prerequisites
:validate_prerequisites
call :log_info "Validating prerequisites..."

docker --version >nul 2>&1
if errorlevel 1 (
    call :log_error "Docker is not installed or not in PATH"
    exit /b 1
)

docker info >nul 2>&1
if errorlevel 1 (
    call :log_error "Docker daemon is not running"
    exit /b 1
)

if not exist "KLIM.Integrations.sln" (
    call :log_error "Must run from solution root directory"
    exit /b 1
)

call :log_success "Prerequisites validated"
goto :eof

REM Build single image
:build_image
set "SERVICE_NAME=%~1"
set "DOCKERFILE_PATH=%~2"
set "IMAGE_TAG=%REGISTRY_PREFIX%/%SERVICE_NAME%:%VERSION%"

call :log_info "Building %IMAGE_TAG%..."

docker build -t "%IMAGE_TAG%" -f "%DOCKERFILE_PATH%" .
if errorlevel 1 (
    call :log_error "Failed to build %IMAGE_TAG%"
    exit /b 1
)

call :log_success "Successfully built %IMAGE_TAG%"

REM Tag as latest if version is not latest
if not "%VERSION%"=="latest" (
    set "LATEST_TAG=%REGISTRY_PREFIX%/%SERVICE_NAME%:latest"
    docker tag "%IMAGE_TAG%" "!LATEST_TAG!"
    call :log_info "Tagged as !LATEST_TAG!"
)

goto :eof

REM Push single image
:push_image
set "SERVICE_NAME=%~1"
set "IMAGE_TAG=%REGISTRY_PREFIX%/%SERVICE_NAME%:%VERSION%"

call :log_info "Pushing %IMAGE_TAG%..."

docker push "%IMAGE_TAG%"
if errorlevel 1 (
    call :log_error "Failed to push %IMAGE_TAG%"
    exit /b 1
)

call :log_success "Successfully pushed %IMAGE_TAG%"

REM Push latest tag if version is not latest
if not "%VERSION%"=="latest" (
    set "LATEST_TAG=%REGISTRY_PREFIX%/%SERVICE_NAME%:latest"
    docker push "!LATEST_TAG!"
    if errorlevel 1 (
        call :log_error "Failed to push !LATEST_TAG!"
        exit /b 1
    )
    call :log_success "Successfully pushed !LATEST_TAG!"
)

goto :eof

REM Main function
:main
call :log_info "Starting Docker build for %SOLUTION_NAME% v%VERSION%"

REM Validate prerequisites
call :validate_prerequisites
if errorlevel 1 exit /b 1

set "BUILD_ERRORS=0"

REM Build Affinity Integration (Web API)
call :build_image "affinity-integration" "src/KLIM.Integrations.Affinity/Dockerfile"
if errorlevel 1 set /a BUILD_ERRORS+=1

REM Build Affinity SQL Writer (Worker Service)
call :build_image "affinity-sql-writer" "src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile"
if errorlevel 1 set /a BUILD_ERRORS+=1

REM Check for build errors
if !BUILD_ERRORS! gtr 0 (
    call :log_error "!BUILD_ERRORS! image(s) failed to build"
    exit /b 1
)

call :log_success "All images built successfully"

REM Push images if requested
if "%PUSH_IMAGES%"=="--push" (
    call :log_info "Pushing images to registry..."
    
    set "PUSH_ERRORS=0"
    
    call :push_image "affinity-integration"
    if errorlevel 1 set /a PUSH_ERRORS+=1
    
    call :push_image "affinity-sql-writer"
    if errorlevel 1 set /a PUSH_ERRORS+=1
    
    if !PUSH_ERRORS! gtr 0 (
        call :log_error "!PUSH_ERRORS! image(s) failed to push"
        exit /b 1
    )
    
    call :log_success "All images pushed successfully"
)

REM Display built images
call :log_info "Built images:"
docker images "%REGISTRY_PREFIX%/*"

call :log_success "Docker build completed successfully!"

REM Usage instructions
echo.
call :log_info "Usage instructions:"
echo   • To run with docker-compose: docker-compose up -d
echo   • To run individual service: docker run -d --env-file .env %REGISTRY_PREFIX%/affinity-integration:%VERSION%
echo   • To push images: %~nx0 %VERSION% --push

goto :eof

REM Show usage
:usage
echo Usage: %~nx0 [VERSION] [--push]
echo.
echo Arguments:
echo   VERSION   Docker image version tag (default: latest)
echo   --push    Push images to registry after building
echo.
echo Examples:
echo   %~nx0                    # Build with 'latest' tag
echo   %~nx0 v1.0.0            # Build with 'v1.0.0' tag
echo   %~nx0 v1.0.0 --push     # Build and push with 'v1.0.0' tag
goto :eof

REM Handle help requests
if "%~1"=="--help" goto usage
if "%~1"=="-h" goto usage

REM Run main function
call :main