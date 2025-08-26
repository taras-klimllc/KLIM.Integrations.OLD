#!/bin/bash

# =============================================================================
# KLIM Integrations - Docker Deployment Script (External RabbitMQ)
# =============================================================================
# This script deploys the KLIM Integrations solution using Docker Compose
# with external RabbitMQ connectivity
# Usage: ./deploy.sh [action] [environment]

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env"
BACKUP_DIR="${SCRIPT_DIR}/backups"
RABBITMQ_TEST_SCRIPT="${SCRIPT_DIR}/test-rabbitmq.sh"

# Default values
ACTION=${1:-deploy}
ENVIRONMENT=${2:-production}

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

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating deployment prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed or not available"
        exit 1
    fi
    
    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        log_error "Docker Compose file not found: ${COMPOSE_FILE}"
        exit 1
    fi
    
    if [[ ! -f "${ENV_FILE}" ]]; then
        log_warning "Environment file not found: ${ENV_FILE}"
        log_info "Creating from template..."
        if [[ -f "${SCRIPT_DIR}/.env.template" ]]; then
            cp "${SCRIPT_DIR}/.env.template" "${ENV_FILE}"
            log_warning "Please edit ${ENV_FILE} with your configuration before deploying"
            exit 1
        else
            log_error "No environment template found"
            exit 1
        fi
    fi
    
    log_success "Prerequisites validated"
}

# Test external RabbitMQ connectivity
test_rabbitmq_connectivity() {
    log_info "Testing external RabbitMQ connectivity..."
    
    # Source environment variables for testing
    if [[ -f "${ENV_FILE}" ]]; then
        # Extract RabbitMQ host from .env file
        local rabbitmq_host
        rabbitmq_host=$(grep "^RABBITMQ__HOST=" "${ENV_FILE}" | cut -d'=' -f2 | tr -d '"' | tr -d ' ')
        
        if [[ -n "$rabbitmq_host" ]]; then
            log_info "Testing connection to RabbitMQ host: $rabbitmq_host"
            
            # Use the test script if available
            if [[ -f "${RABBITMQ_TEST_SCRIPT}" && -x "${RABBITMQ_TEST_SCRIPT}" ]]; then
                if "${RABBITMQ_TEST_SCRIPT}" "$rabbitmq_host"; then
                    log_success "RabbitMQ connectivity test passed"
                    return 0
                else
                    log_warning "RabbitMQ connectivity test failed - deployment may encounter issues"
                    return 1
                fi
            else
                # Fallback to basic port test
                if command -v nc &> /dev/null; then
                    if nc -z -w5 "$rabbitmq_host" 5672; then
                        log_success "Basic RabbitMQ port test passed"
                        return 0
                    else
                        log_warning "Cannot connect to RabbitMQ port 5672 on $rabbitmq_host"
                        return 1
                    fi
                else
                    log_warning "Cannot test RabbitMQ connectivity - nc not available"
                    return 1
                fi
            fi
        else
            log_warning "RABBITMQ__HOST not found in environment file"
            return 1
        fi
    else
        log_warning "Cannot test RabbitMQ connectivity - no environment file"
        return 1
    fi
}

# Get Docker Compose command
get_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

# Deploy services
deploy() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    log_info "Deploying KLIM Integrations (${ENVIRONMENT}) with external RabbitMQ..."
    
    # Test RabbitMQ connectivity first
    if ! test_rabbitmq_connectivity; then
        log_warning "RabbitMQ connectivity issues detected. Continue anyway? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_error "Deployment cancelled due to RabbitMQ connectivity issues"
            exit 1
        fi
    fi
    
    # Pull latest images
    log_info "Pulling latest images..."
    $compose_cmd -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" pull
    
    # Start services
    log_info "Starting integration services..."
    $compose_cmd -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d
    
    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    sleep 15
    
    # Check service status
    log_info "Service status:"
    $compose_cmd -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" ps
    
    # Test health endpoints
    log_info "Testing health endpoints..."
    local max_attempts=30
    local attempt=1
    local port
    port=$(grep "^AFFINITY_INTEGRATION_PORT=" "${ENV_FILE}" | cut -d'=' -f2 | tr -d '"' | tr -d ' ')
    port=${port:-8088}
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -f -s "http://localhost:${port}/health" > /dev/null; then
            log_success "Affinity Integration service is healthy"
            break
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Affinity Integration service failed health check after ${max_attempts} attempts"
            show_logs
            return 1
        fi
        
        log_info "Attempt ${attempt}/${max_attempts}: Waiting for health check..."
        sleep 5
        ((attempt++))
    done
    
    # Show RabbitMQ connection status in health check
    log_info "Checking RabbitMQ integration status..."
    local health_response
    if health_response=$(curl -s "http://localhost:${port}/health" 2>/dev/null); then
        log_info "Health check response:"
        echo "$health_response" | python3 -m json.tool 2>/dev/null || echo "$health_response"
    fi
    
    log_success "Deployment completed successfully!"
    
    # Show service URLs
    echo ""
    log_info "Service URLs:"
    echo "  • Affinity Integration API: http://localhost:${port}"
    echo "  • Health Check: http://localhost:${port}/health"
    echo "  • External RabbitMQ Management: http://localhost:15672 (guest/guest)"
    
    # Show management commands
    echo ""
    log_info "Management commands:"
    echo "  • View logs: $0 logs"
    echo "  • Stop services: $0 stop"
    echo "  • Restart services: $0 restart"
    echo "  • Update services: $0 update"
    echo "  • Test RabbitMQ: ./test-rabbitmq.sh"
}

# Stop services
stop() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    log_info "Stopping KLIM Integrations services (RabbitMQ remains running)..."
    $compose_cmd -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" down
    log_success "Integration services stopped"
    log_info "Note: External RabbitMQ container remains running"
}

# Restart services
restart() {
    log_info "Restarting KLIM Integrations services..."
    stop
    deploy
}

# Update services
update() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    log_info "Updating KLIM Integrations services..."
    
    # Create backup
    backup_configuration
    
    # Pull latest images
    log_info "Pulling latest images..."
    $compose_cmd -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" pull
    
    # Recreate and restart services
    log_info "Recreating services with latest images..."
    $compose_cmd -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d --force-recreate
    
    log_success "Services updated successfully"
}

# Show logs
show_logs() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    local service=${2:-""}
    
    if [[ -n "$service" ]]; then
        log_info "Showing logs for $service..."
        $compose_cmd -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" logs -f --tail=100 "$service"
    else
        log_info "Showing logs for all integration services..."
        $compose_cmd -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" logs -f --tail=100
    fi
}

# Show service status
status() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    log_info "Integration service status:"
    $compose_cmd -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" ps
    
    echo ""
    log_info "External RabbitMQ container status:"
    if docker ps --filter "name=competent_burnell" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | grep -v "NAMES"; then
        echo "RabbitMQ container is running"
    else
        log_warning "External RabbitMQ container 'competent_burnell' not found"
    fi
    
    echo ""
    log_info "Docker images:"
    docker images "klim/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
}

# Test RabbitMQ connectivity
test_rabbitmq() {
    if [[ -f "${RABBITMQ_TEST_SCRIPT}" ]]; then
        log_info "Running RabbitMQ connectivity test..."
        
        # Extract host from .env file
        local rabbitmq_host
        if [[ -f "${ENV_FILE}" ]]; then
            rabbitmq_host=$(grep "^RABBITMQ__HOST=" "${ENV_FILE}" | cut -d'=' -f2 | tr -d '"' | tr -d ' ')
        fi
        rabbitmq_host=${rabbitmq_host:-"localhost"}
        
        "${RABBITMQ_TEST_SCRIPT}" "$rabbitmq_host"
    else
        log_error "RabbitMQ test script not found: ${RABBITMQ_TEST_SCRIPT}"
        exit 1
    fi
}

# Backup configuration
backup_configuration() {
    mkdir -p "${BACKUP_DIR}"
    local backup_name="config-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    log_info "Creating configuration backup: ${backup_name}"
    mkdir -p "${backup_path}"
    
    # Backup environment file
    if [[ -f "${ENV_FILE}" ]]; then
        cp "${ENV_FILE}" "${backup_path}/.env"
    fi
    
    # Backup compose file
    cp "${COMPOSE_FILE}" "${backup_path}/docker-compose.yml"
    
    log_success "Configuration backed up to ${backup_path}"
}

# Cleanup old resources
cleanup() {
    log_info "Cleaning up old Docker resources (integration services only)..."
    
    # Remove stopped containers
    docker container prune -f
    
    # Remove unused images (be careful with external RabbitMQ)
    docker image prune -f
    
    # Remove unused networks
    docker network prune -f
    
    log_success "Cleanup completed"
    log_warning "External RabbitMQ resources were not affected"
}

# Show usage information
usage() {
    echo "Usage: $0 [action] [service]"
    echo ""
    echo "Actions:"
    echo "  deploy       Deploy integration services (default)"
    echo "  stop         Stop integration services"
    echo "  restart      Restart integration services"
    echo "  update       Update services with latest images"
    echo "  logs         Show service logs"
    echo "  status       Show service status"
    echo "  test-rabbitmq Test external RabbitMQ connectivity"
    echo "  backup       Backup current configuration"
    echo "  cleanup      Clean up old Docker resources"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Deploy all integration services"
    echo "  $0 logs                      # Show logs for all services"
    echo "  $0 logs affinity-integration # Show logs for specific service"
    echo "  $0 stop                      # Stop integration services"
    echo "  $0 test-rabbitmq             # Test external RabbitMQ connectivity"
    echo ""
    echo "Note: This deployment connects to external RabbitMQ (competent_burnell container)"
    echo "      RabbitMQ is not managed by this deployment script"
}

# Main function
main() {
    case "$ACTION" in
        "deploy")
            validate_prerequisites
            deploy
            ;;
        "stop")
            stop
            ;;
        "restart")
            validate_prerequisites
            restart
            ;;
        "update")
            validate_prerequisites
            update
            ;;
        "logs")
            show_logs "$@"
            ;;
        "status")
            status
            ;;
        "test-rabbitmq")
            test_rabbitmq
            ;;
        "backup")
            backup_configuration
            ;;
        "cleanup")
            cleanup
            ;;
        "--help"|"-h")
            usage
            ;;
        *)
            log_error "Unknown action: $ACTION"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"