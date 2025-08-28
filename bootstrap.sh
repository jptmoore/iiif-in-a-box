#!/bin/bash
# IIIF-In-A-Box Bootstrap Script
set -e

# Configuration - clone to parent directory
PROJECTS=(
    "../tamerlane:https://github.com/jptmoore/tamerlane.git"
    "../miiify:https://github.com/jptmoore/miiify.git" 
    "../annosearch:https://github.com/jptmoore/annosearch.git"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to clone or update a project
update_project() {
    local project_path="$1"
    local repo_url="$2"
    local project_name=$(basename "$project_path")
    
    if [ -d "$project_path" ]; then
        log_info "Updating $project_name..."
        cd "$project_path"
        
        # Check if it's a git repository
        if [ ! -d ".git" ]; then
            log_error "$project_name exists but is not a git repository!"
            cd - > /dev/null
            return 1
        fi
        
        # Get current branch
        current_branch=$(git branch --show-current)
        log_info "$project_name on branch: $current_branch"
        
        # Fetch and pull latest changes with fast-forward only
        git fetch origin
        git pull --ff-only origin "$current_branch" || {
            log_warning "$project_name has diverged from upstream. Manual intervention required."
            log_info "To resolve: cd $project_path && git pull --rebase origin $current_branch"
            cd - > /dev/null
            return 1
        }
        
        log_success "$project_name updated successfully"
        cd - > /dev/null
    else
        log_info "Cloning $project_name..."
        git clone "$repo_url" "$project_path"
        log_success "$project_name cloned successfully"
    fi
}

# Function to check if docker and docker-compose are available
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v git &> /dev/null; then
        log_error "git is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "docker-compose is not installed or not in PATH"
        exit 1
    fi
    
    log_success "All dependencies are available"
}

# Function to build and start services
build_and_start() {
    local build_args=""
    local compose_file="docker-compose.yml"
    
    # Check for proxy-friendly build flag
    if [ "$PROXY_FRIENDLY" = "true" ]; then
        log_warning "Using proxy-friendly build options (skip TLS verification)"
        build_args="--build-arg BUILDKIT_INLINE_CACHE=1"
        compose_file="docker-compose.proxy.yml"
        export DOCKER_BUILDKIT=0
        export COMPOSE_DOCKER_CLI_BUILD=0
    fi
    
    log_info "Building and starting services..."
    
    cd proxy
    
    # Stop any running services
    if docker-compose -f "$compose_file" ps 2>/dev/null | grep -q "Up"; then
        log_info "Stopping existing services..."
        docker-compose -f "$compose_file" down
    fi
    
    # Build services
    log_info "Building Docker services..."
    if [ "$PROXY_FRIENDLY" = "true" ]; then
        log_info "Building with proxy-friendly options using $compose_file..."
        docker-compose -f "$compose_file" build --no-cache $build_args
    else
        docker-compose -f "$compose_file" build --no-cache
    fi
    
    # Start services
    log_info "Starting services..."
    docker-compose -f "$compose_file" up -d
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 10
    
    # Check service status
    if docker-compose ps | grep -q "Exit"; then
        log_error "Some services failed to start!"
        docker-compose logs
        cd - > /dev/null
        return 1
    fi
    
    log_success "All services are running!"
    log_info "IIIF-In-A-Box is available at: http://localhost:8080"
    log_info "Tamerlane viewer at: http://localhost:8080/viewer/"
    
    cd - > /dev/null
}

# Function to show service status
show_status() {
    log_info "Service Status:"
    cd proxy
    # Try proxy compose file first, then regular
    if [ -f "docker-compose.proxy.yml" ] && docker-compose -f docker-compose.proxy.yml ps 2>/dev/null | grep -q "Up\|Exit"; then
        docker-compose -f docker-compose.proxy.yml ps
    else
        docker-compose ps
    fi
    cd - > /dev/null
}

# Main execution
main() {
    log_info "IIIF-In-A-Box Bootstrap Script"
    log_info "=============================="
    
    # Check dependencies
    check_dependencies
    
    # Update/clone projects
    log_info "Updating project dependencies..."
    for project_info in "${PROJECTS[@]}"; do
        IFS=':' read -r project_path repo_url <<< "$project_info"
        update_project "$project_path" "$repo_url"
    done
    
    # Parse command line arguments
    case "${1:-build}" in
        "update-only")
            log_success "Projects updated. Run './bootstrap.sh build' to build and start services."
            ;;
        "build")
            build_and_start
            ;;
        "build-proxy")
            log_info "Building with proxy-friendly options..."
            PROXY_FRIENDLY=true build_and_start
            ;;
        "status")
            show_status
            ;;
        "stop")
            log_info "Stopping services..."
            cd proxy
            docker-compose down
            cd - > /dev/null
            log_success "Services stopped"
            ;;
        "restart")
            log_info "Restarting services..."
            cd proxy
            docker-compose restart
            cd - > /dev/null
            log_success "Services restarted"
            ;;
        "logs")
            cd proxy
            docker-compose logs -f
            cd - > /dev/null
            ;;
        *)
            echo "Usage: $0 [update-only|build|build-proxy|status|stop|restart|logs]"
            echo ""
            echo "Commands:"
            echo "  build       - Update projects and build/start services (default)"
            echo "  build-proxy - Build with proxy-friendly options (for corporate networks)"
            echo "  update-only - Only update git repositories"
            echo "  status      - Show service status"
            echo "  stop        - Stop all services"
            echo "  restart     - Restart all services"
            echo "  logs        - Show service logs"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
