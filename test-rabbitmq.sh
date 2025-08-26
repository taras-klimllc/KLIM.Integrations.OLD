#!/bin/bash

# =============================================================================
# KLIM Integrations - RabbitMQ Connectivity Test Script
# =============================================================================
# Tests connectivity to external RabbitMQ instance
# Usage: ./test-rabbitmq.sh [host] [port]
# 
# For Windows PowerShell users, see the PowerShell section below or use:
# PowerShell -ExecutionPolicy Bypass -File test-rabbitmq.ps1

set -e  # Exit on any error

# Configuration
RABBITMQ_HOST=${1:-"localhost"}
RABBITMQ_PORT=${2:-"5672"}
RABBITMQ_MGMT_PORT="15672"
RABBITMQ_USER="guest"
RABBITMQ_PASS="guest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

test_amqp_connection() {
    log_info "Testing AMQP connection to ${RABBITMQ_HOST}:${RABBITMQ_PORT}..."
    
    if command -v nc &> /dev/null; then
        if nc -z -w5 ${RABBITMQ_HOST} ${RABBITMQ_PORT}; then
            log_success "AMQP port ${RABBITMQ_PORT} is accessible"
            return 0
        else
            log_error "AMQP port ${RABBITMQ_PORT} is not accessible"
            return 1
        fi
    elif command -v telnet &> /dev/null; then
        if timeout 5 telnet ${RABBITMQ_HOST} ${RABBITMQ_PORT} </dev/null 2>/dev/null | grep -q Connected; then
            log_success "AMQP port ${RABBITMQ_PORT} is accessible"
            return 0
        else
            log_error "AMQP port ${RABBITMQ_PORT} is not accessible"
            return 1
        fi
    else
        log_warning "Neither nc nor telnet available for port testing"
        return 1
    fi
}

test_management_api() {
    log_info "Testing RabbitMQ Management API at http://${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}..."
    
    if command -v curl &> /dev/null; then
        local response
        if response=$(curl -s -u ${RABBITMQ_USER}:${RABBITMQ_PASS} \
            -w "HTTP_%{http_code}" \
            "http://${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}/api/overview" 2>/dev/null); then
            
            if [[ $response == *"HTTP_200" ]]; then
                log_success "Management API is accessible and authenticated"
                return 0
            else
                log_error "Management API returned non-200 response: $response"
                return 1
            fi
        else
            log_error "Failed to connect to Management API"
            return 1
        fi
    else
        log_warning "curl not available for API testing"
        log_info "For Windows PowerShell, use: Invoke-RestMethod with Basic Auth"
        return 1
    fi
}

test_exchange_exists() {
    local exchange_name="klim.events"
    log_info "Checking if exchange '${exchange_name}' exists..."
    
    if command -v curl &> /dev/null; then
        local response
        if response=$(curl -s -u ${RABBITMQ_USER}:${RABBITMQ_PASS} \
            -w "HTTP_%{http_code}" \
            "http://${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}/api/exchanges/%2F/${exchange_name}" 2>/dev/null); then
            
            if [[ $response == *"HTTP_200" ]]; then
                log_success "Exchange '${exchange_name}' exists"
                return 0
            elif [[ $response == *"HTTP_404" ]]; then
                log_warning "Exchange '${exchange_name}' does not exist"
                return 1
            else
                log_error "Error checking exchange: $response"
                return 1
            fi
        else
            log_error "Failed to check exchange existence"
            return 1
        fi
    else
        log_warning "curl not available for exchange testing"
        return 1
    fi
}

test_docker_connectivity() {
    log_info "Testing Docker-specific connectivity options..."
    
    # Test host.docker.internal (Docker Desktop)
    if [[ "$RABBITMQ_HOST" != "host.docker.internal" ]]; then
        log_info "Testing host.docker.internal fallback..."
        if nc -z -w5 host.docker.internal ${RABBITMQ_PORT} 2>/dev/null; then
            log_success "host.docker.internal:${RABBITMQ_PORT} is accessible"
        else
            log_warning "host.docker.internal:${RABBITMQ_PORT} is not accessible"
        fi
    fi
    
    # Test localhost fallback
    if [[ "$RABBITMQ_HOST" != "localhost" ]]; then
        log_info "Testing localhost fallback..."
        if nc -z -w5 localhost ${RABBITMQ_PORT} 2>/dev/null; then
            log_success "localhost:${RABBITMQ_PORT} is accessible"
        else
            log_warning "localhost:${RABBITMQ_PORT} is not accessible"
        fi
    fi
}

show_container_info() {
    log_info "Checking for RabbitMQ containers..."
    
    if command -v docker &> /dev/null; then
        local containers
        if containers=$(docker ps --filter "ancestor=*rabbitmq*" --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}" 2>/dev/null); then
            if [[ -n "$containers" && "$containers" != *"NAMES"* ]]; then
                echo "$containers"
            else
                log_info "No RabbitMQ containers found with 'docker ps'"
            fi
        fi
        
        # Check for the specific container mentioned
        if docker inspect competent_burnell &>/dev/null; then
            local container_ip
            container_ip=$(docker inspect competent_burnell --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
            if [[ -n "$container_ip" ]]; then
                log_info "Found RabbitMQ container 'competent_burnell' at IP: $container_ip"
                
                # Test direct container IP
                log_info "Testing direct container IP connectivity..."
                if nc -z -w5 ${container_ip} ${RABBITMQ_PORT} 2>/dev/null; then
                    log_success "Direct container IP ${container_ip}:${RABBITMQ_PORT} is accessible"
                else
                    log_warning "Direct container IP ${container_ip}:${RABBITMQ_PORT} is not accessible"
                fi
            fi
        fi
    else
        log_warning "Docker not available for container inspection"
    fi
}

show_powershell_examples() {
    log_info "PowerShell equivalents for Windows users:"
    echo ""
    echo "# Test AMQP port connectivity:"
    echo "Test-NetConnection -ComputerName ${RABBITMQ_HOST} -Port ${RABBITMQ_PORT}"
    echo ""
    echo "# Test RabbitMQ Management API:"
    echo "\$cred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(\"guest:guest\"))"
    echo "\$headers = @{Authorization = \"Basic \$cred\"}"
    echo "Invoke-RestMethod -Uri \"http://${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}/api/overview\" -Headers \$headers"
    echo ""
    echo "# Check if exchange exists:"
    echo "Invoke-RestMethod -Uri \"http://${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}/api/exchanges/%2F/klim.events\" -Headers \$headers"
    echo ""
    echo "# Test health endpoint:"
    echo "Invoke-RestMethod -Uri \"http://localhost:8088/health\""
    echo ""
}

main() {
    echo "=============================================================================="
    echo "KLIM Integrations - RabbitMQ Connectivity Test"
    echo "=============================================================================="
    echo "Testing RabbitMQ connectivity to: ${RABBITMQ_HOST}:${RABBITMQ_PORT}"
    echo ""
    
    local tests_passed=0
    local total_tests=0
    
    # Test 1: AMQP Connection
    ((total_tests++))
    if test_amqp_connection; then
        ((tests_passed++))
    fi
    echo ""
    
    # Test 2: Management API
    ((total_tests++))
    if test_management_api; then
        ((tests_passed++))
    fi
    echo ""
    
    # Test 3: Exchange Existence
    ((total_tests++))
    if test_exchange_exists; then
        ((tests_passed++))
    fi
    echo ""
    
    # Additional Docker-specific tests
    test_docker_connectivity
    echo ""
    
    # Container information
    show_container_info
    echo ""
    
    # PowerShell examples for Windows users
    show_powershell_examples
    echo ""
    
    # Summary
    echo "=============================================================================="
    echo "Test Summary: ${tests_passed}/${total_tests} tests passed"
    
    if [[ $tests_passed -eq $total_tests ]]; then
        log_success "All connectivity tests passed! RabbitMQ is ready for KLIM Integrations."
    elif [[ $tests_passed -gt 0 ]]; then
        log_warning "Some tests passed. RabbitMQ may be partially accessible."
    else
        log_error "All tests failed. Check RabbitMQ configuration and network connectivity."
        echo ""
        log_info "For Windows PowerShell users:"
        echo "1. Use the PowerShell commands shown above"
        echo "2. Or create and run the PowerShell version: test-rabbitmq.ps1"
        exit 1
    fi
    
    echo ""
    echo "Recommended .env configuration:"
    echo "RABBITMQ__HOST=${RABBITMQ_HOST}"
    echo "RABBITMQ__USERNAME=${RABBITMQ_USER}"
    echo "RABBITMQ__PASSWORD=${RABBITMQ_PASS}"
    echo "RABBITMQ__EXCHANGENAME=klim.events"
    echo ""
}

# Show usage information
usage() {
    echo "Usage: $0 [host] [port]"
    echo ""
    echo "Arguments:"
    echo "  host    RabbitMQ hostname (default: localhost)"
    echo "  port    RabbitMQ AMQP port (default: 5672)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Test localhost:5672"
    echo "  $0 host.docker.internal      # Test Docker Desktop host"
    echo "  $0 172.17.0.2               # Test direct container IP"
    echo "  $0 rabbitmq.company.com      # Test external host"
    echo ""
    echo "Environment Variables:"
    echo "  RABBITMQ_HOST, RABBITMQ_PORT - Override default values"
    echo ""
    echo "Windows PowerShell Users:"
    echo "  Use PowerShell commands shown in the output above, or"
    echo "  Create test-rabbitmq.ps1 with PowerShell equivalents"
    echo ""
}

# Handle help requests
if [[ "${1}" == "--help" ]] || [[ "${1}" == "-h" ]]; then
    usage
    exit 0
fi

# Run main function
main