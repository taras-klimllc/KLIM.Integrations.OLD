#!/bin/bash

# =============================================================================
# KLIM Integrations - Docker Build Script (Enhanced)
# =============================================================================
# Builds Docker images with optimization and development features
# Usage: ./build-docker.sh [version] [--push] [--dev] [--no-cache]

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=${1:-"latest"}
PUSH=false
DEV_MODE=false
NO_CACHE=false
PARALLEL_BUILD=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH=true
            shift
            ;;
        --dev)
            DEV_MODE=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --no-parallel)
            PARALLEL_BUILD=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [version] [--push] [--dev] [--no-cache] [--no-parallel]"
            echo ""
            echo "Arguments:"
            echo "  version        Docker image version tag (default: latest)"
            echo "  --push         Push images to registry after building"
            echo "  --dev          Build development images with debug symbols"
            echo "  --no-cache     Build without using Docker cache"
            echo "  --no-parallel  Build images sequentially instead of parallel"
            echo "  --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                          # Build latest version"
            echo "  $0 v1.2.3                  # Build specific version"
            echo "  $0 v1.2.3 --push          # Build and push to registry"
            echo "  $0 --dev                   # Build development version"
            exit 0
            ;;
        *)
            if [[ "$1" != --* ]]; then
                VERSION="$1"
            fi
            shift
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Image configuration
IMAGES=(
    "klim/affinity-integration:src/KLIM.Integrations.Affinity/Dockerfile"
    "klim/affinity-sql-writer:src/KLIM.Integrations.Affinity.SqlWriter/Dockerfile"
)

# Build function
build_image() {
    local image_name="$1"
    local dockerfile="$2"
    local full_tag="${image_name}:${VERSION}"
    
    log_info "Building ${full_tag}..."
    
    # Build arguments
    local build_args=(
        "--file" "$dockerfile"
        "--tag" "$full_tag"
    )
    
    if [[ "$NO_CACHE" == true ]]; then
        build_args+=("--no-cache")
    fi
    
    if [[ "$DEV_MODE" == true ]]; then
        build_args+=("--target" "runtime")
        build_args+=("--build-arg" "CONFIGURATION=Debug")
        full_tag="${image_name}:${VERSION}-dev"
        build_args[3]="$full_tag"  # Update tag
    fi
    
    # Add latest tag for convenience
    if [[ "$VERSION" != "latest" ]]; then
        build_args+=("--tag" "${image_name}:latest")
    fi
    
    build_args+=(".")
    
    # Execute build
    if docker build "${build_args[@]}"; then
        log_success "Built ${full_tag}"
        
        # Push if requested
        if [[ "$PUSH" == true ]]; then
            log_info "Pushing ${full_tag}..."
            if docker push "$full_tag"; then
                log_success "Pushed ${full_tag}"
                
                # Push latest tag if applicable
                if [[ "$VERSION" != "latest" ]]; then
                    docker push "${image_name}:latest"
                    log_success "Pushed ${image_name}:latest"
                fi
            else
                log_error "Failed to push ${full_tag}"
                return 1
            fi
        fi
        
        return 0
    else
        log_error "Failed to build ${full_tag}"
        return 1
    fi
}

# Main execution
main() {
    cd "$SCRIPT_DIR"
    
    log_info "KLIM Integrations - Docker Build"
    log_info "Version: $VERSION"
    log_info "Development mode: $DEV_MODE"
    log_info "Push to registry: $PUSH"
    log_info "Use cache: $([[ "$NO_CACHE" == true ]] && echo "false" || echo "true")"
    log_info "Parallel build: $PARALLEL_BUILD"
    echo ""
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Build images
    local failed_builds=()
    
    if [[ "$PARALLEL_BUILD" == true ]]; then
        log_info "Building images in parallel..."
        
        # Start builds in background
        local pids=()
        for image_info in "${IMAGES[@]}"; do
            local image_name="${image_info%%:*}"
            local dockerfile="${image_info#*:}"
            
            build_image "$image_name" "$dockerfile" &
            pids+=($!)
        done
        
        # Wait for all builds to complete
        local all_success=true
        for i in "${!pids[@]}"; do
            local pid="${pids[$i]}"
            local image_name="${IMAGES[$i]%%:*}"
            
            if wait "$pid"; then
                log_success "Parallel build completed: $image_name"
            else
                log_error "Parallel build failed: $image_name"
                failed_builds+=("$image_name")
                all_success=false
            fi
        done
    else
        log_info "Building images sequentially..."
        
        for image_info in "${IMAGES[@]}"; do
            local image_name="${image_info%%:*}"
            local dockerfile="${image_info#*:}"
            
            if ! build_image "$image_name" "$dockerfile"; then
                failed_builds+=("$image_name")
            fi
        done
    fi
    
    echo ""
    
    # Summary
    if [[ ${#failed_builds[@]} -eq 0 ]]; then
        log_success "All images built successfully!"
        
        # Show built images
        echo ""
        log_info "Built images:"
        for image_info in "${IMAGES[@]}"; do
            local image_name="${image_info%%:*}"
            local tag_suffix=""
            [[ "$DEV_MODE" == true ]] && tag_suffix="-dev"
            echo "  • ${image_name}:${VERSION}${tag_suffix}"
            [[ "$VERSION" != "latest" ]] && echo "  • ${image_name}:latest"
        done
        
        # Show next steps
        echo ""
        log_info "Next steps:"
        echo "  • Test images: docker-compose up"
        echo "  • View images: docker images 'klim/*'"
        echo "  • Deploy: ./deploy.sh deploy"
        
    else
        log_error "Failed to build ${#failed_builds[@]} image(s): ${failed_builds[*]}"
        exit 1
    fi
}

# Execute main function
main