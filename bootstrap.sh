#!/bin/bash
# IIIF-In-A-Box Bootstrap Script v2
# Uses Miiify v2 with separate input/output directories
#
# This script is the single entry point. The heavy lifting is in scripts/:
#   config-helpers.sh     - read project config + metadata/provider extraction
#   image-helpers.sh      - process_images + validate_annotation_naming
#   miiify-helpers.sh     - import/compile annotations via Miiify
#   manifest-helpers.sh   - generate IIIF Collections and Manifests
#   web-helpers.sh        - generate viewer pages and stage static content
#   annosearch-helpers.sh - AnnoSearch index management + wait_for_* probes
#   service-helpers.sh    - Docker network / Tamerlane image / lifecycle
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${BLUE}[INFO]${NC} $1" || true; }
log_step() { echo -e "  ${BLUE}→${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default configuration
DEFAULT_OUTPUT_DIR="./output"
DEFAULT_HOSTNAME="http://localhost:8080"
VERBOSE=false
DOCKER_COMPOSE_CMD="docker compose"

# Version and script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IIIF_VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "unknown")

# Load helper modules. Order matters: manifest/web/service depend on
# log_*, config, image, miiify, and annosearch helpers.
source "${SCRIPT_DIR}/scripts/config-helpers.sh"
source "${SCRIPT_DIR}/scripts/image-helpers.sh"
source "${SCRIPT_DIR}/scripts/miiify-helpers.sh"
source "${SCRIPT_DIR}/scripts/annosearch-helpers.sh"
source "${SCRIPT_DIR}/scripts/manifest-helpers.sh"
source "${SCRIPT_DIR}/scripts/web-helpers.sh"
source "${SCRIPT_DIR}/scripts/service-helpers.sh"
source "${SCRIPT_DIR}/scripts/test-helpers.sh"

# Function to show help
show_help() {
    cat << EOF
IIIF-In-A-Box Bootstrap Script v2 (Miiify v2)

Usage: $0 [OPTIONS] [COMMAND]

Options:
  --input-dir, -i DIR         Input directory containing source data (required for build)
                               Example: /home/john/git/domesday-in-a-box
  --output-dir, -o DIR        Output directory for generated files
                               (default: ./output)
  --hostname, --host URL      Base URL for the IIIF service 
                               Port defaults to 80 if not specified
                               Examples: http://example.com (port 80)
                                        http://localhost:8080 (port 8080)
                               (default: http://localhost:8080)
  --pull                       Force pull latest Docker images before starting
  --verbose, -v                Show detailed build output (default: minimal progress)
  --help, -h                   Show this help message

Commands:
  build                        - Build IIIF service from input directory
  status                       - Show service status
  stop                         - Stop all services
  restart                      - Restart all services
  logs                         - Show service logs
  clean                        - Stop services and clean output directory
  test                         - Run smoke tests against the running stack
  maintenance                  - Enable maintenance mode (stops services, shows maintenance page)

Examples:
  # Build from input directory (first time)
  $0 build --input-dir /home/john/git/domesday-in-a-box
  
  # Build with custom output directory
  $0 build -i /home/john/git/domesday-in-a-box -o /home/john/iiif-output
  
  # Build for deployment with external hostname
  $0 build -i ~/domesday-in-a-box --hostname http://192.168.1.100
  
  # Build with custom port
  $0 build -i ~/domesday-in-a-box --hostname http://example.com:8080
  
  # Check service status
  $0 status
  
  # View logs
  $0 logs
  
  # Stop all services
  $0 stop
  
  # Clean everything (stop services, remove output)
  $0 clean

EOF
}

# Function to parse command line arguments
parse_arguments() {
    INPUT_DIR=""
    OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
    HOSTNAME="$DEFAULT_HOSTNAME"
    FORCE_PULL=false
    VERBOSE=false
    COMMAND=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --input-dir|-i)
                INPUT_DIR="$2"
                shift 2
                ;;
            --output-dir|-o)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --hostname|--host)
                HOSTNAME="$2"
                shift 2
                ;;
            --pull)
                FORCE_PULL=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            build|status|stop|restart|logs|clean|test|maintenance)
                COMMAND="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set default command if none provided
    if [ -z "$COMMAND" ]; then
        COMMAND="build"
    fi
    
    # Validate input directory for build command
    if [ "$COMMAND" = "build" ] && [ -z "$INPUT_DIR" ]; then
        log_error "Input directory is required for build command"
        log_info "Use: $0 build --input-dir /path/to/input"
        exit 1
    fi
}

# Function to check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        log_error "docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check for docker compose
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        log_error "Neither 'docker compose' nor 'docker-compose' is available"
        exit 1
    fi
    
    # Check for rsync (for image copying)
    if ! command -v rsync &> /dev/null; then
        log_warning "rsync not found, will use cp for copying files"
    fi
    
    log_success "All dependencies are available"
}

# Function to build project
build_project() {
    echo ""
    echo -e "${BLUE}IIIF-in-a-Box v${IIIF_VERSION}${NC}"
    echo -e "  Input:    $INPUT_DIR"
    echo -e "  Output:   $OUTPUT_DIR"
    echo -e "  Hostname: $HOSTNAME"
    echo ""
    
    # Step 0: Stop any running services to avoid lock file issues
    log_step "Stopping any running services..."
    stop_services
    
    # Also stop maintenance mode if it's running
    docker compose -f nginx/docker-compose.maintenance.yml down 2>/dev/null || true
    
    # Step 1: Validate input directory
    log_step "Validating input directory..."
    if ! validate_input_directory "$INPUT_DIR"; then
        log_error "Input directory validation failed"
        exit 1
    fi
    
    # Step 2: Read configuration
    log_step "Reading configuration..."
    if ! read_project_config "$INPUT_DIR"; then
        log_error "Failed to read project configuration"
        exit 1
    fi
    
    # Step 2a: Check if yq is installed (required for YAML parsing)
    if ! check_yq_dependency; then
        log_error "yq is required but not installed"
        exit 1
    fi
    
    log_info "Project: $PROJECT_NAME | Title: $PROJECT_TITLE"
    
    # Step 3: Validate annotation naming
    log_step "Validating annotations..."
    if ! validate_annotation_naming "$INPUT_DIR"; then
        log_error "Annotation naming validation failed"
        exit 1
    fi
    
    # Step 4: Clean and create output directory structure
    log_step "Preparing output directory..."
    # Remove all contents to prevent any old data contamination
    rm -rf "$OUTPUT_DIR"/* 2>/dev/null || true
    mkdir -p "$OUTPUT_DIR"/{miiify/{git_store,pack_store},web/{iiif,pages,images},annosearch/qwdata,logs}
    
    # Store current project name for reference
    echo "$PROJECT_NAME" > "$OUTPUT_DIR/.project"
    
    # Step 5: Process images
    log_step "Processing images..."
    if ! process_images "$INPUT_DIR" "$OUTPUT_DIR" "$PROJECT_NAME"; then
        log_error "Image processing failed"
        exit 1
    fi

    # Step 6: Run Miiify workflow (import → compile)
    log_step "Running Miiify workflow..."
    if ! miiify_full_workflow "$INPUT_DIR" "$OUTPUT_DIR"; then
        log_error "Miiify workflow failed"
        exit 1
    fi
    
    # Step 7: Generate IIIF manifests
    log_step "Generating IIIF manifests..."
    if ! generate_manifest "$PROJECT_NAME" "$PROJECT_TITLE" "$PROJECT_DESCRIPTION" "$HOSTNAME" "$INPUT_DIR"; then
        log_error "Manifest generation failed"
        exit 1
    fi
    
    # Step 8: Generate HTML viewer page
    log_step "Generating viewer page..."
    if ! generate_viewer_page "$PROJECT_NAME" "$VIEWER_MANIFEST" "$PROJECT_TITLE" "$PROJECT_DESCRIPTION" "$HOSTNAME" "${MANIFEST_TYPE:-Collection}"; then
        log_error "Page generation failed"
        exit 1
    fi
    
    # Step 9: Setup web content
    log_step "Setting up web content..."
    setup_web_content
    
    # Step 10: Create Docker network
    create_docker_network
    
    # Step 10.5: Prepare Tamerlane image
    log_step "Preparing Tamerlane image..."
    if ! prepare_tamerlane_image; then
        log_error "Failed to prepare Tamerlane image"
        exit 1
    fi
    
    # Step 11: Start all services
    log_step "Starting services..."
    if ! start_all_services; then
        log_error "Failed to start all services"
        exit 1
    fi
    
    # Step 12: Wait for AnnoSearch to be ready
    log_step "Waiting for AnnoSearch..."
    if ! wait_for_annosearch; then
        log_warning "AnnoSearch not ready, skipping search indexing"
    else
        # Step 13: Create search index and load data
        log_step "Indexing search data..."
        # Use the derived manifest name for indexing, not the project name
        if create_annosearch_index "$MANIFEST_NAME"; then
            load_annosearch_data "$MANIFEST_NAME" "$HOSTNAME" || log_warning "Failed to load data into AnnoSearch"
        fi
    fi
    
    # Store current project name and build version for future reference
    echo "$PROJECT_NAME" > "$OUTPUT_DIR/.project"
    echo "$IIIF_VERSION" > "$OUTPUT_DIR/.version"

    # Step 14: Smoke test the running stack (non-fatal)
    log_step "Running smoke tests..."
    if ! run_smoke_tests "$MANIFEST_NAME"; then
        log_warning "Some smoke tests failed — service is up but not fully healthy"
    fi

    print_build_summary "$PROJECT_NAME" "$MANIFEST_NAME" "$PROJECT_TITLE" "$HOSTNAME"
}

# Main execution
main() {
    parse_arguments "$@"
    check_dependencies
    
    # Convert paths to absolute paths (required for Docker volume mounts)
    if [ -n "$INPUT_DIR" ]; then
        INPUT_DIR="$(cd "$INPUT_DIR" && pwd)" || {
            log_error "Invalid input directory: $INPUT_DIR"
            exit 1
        }
    fi
    
    # Convert OUTPUT_DIR to absolute path, creating it if it doesn't exist
    mkdir -p "$OUTPUT_DIR"
    OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
    
    case "$COMMAND" in
        build)
            build_project
            ;;
        status)
            show_status
            ;;
        stop)
            stop_services
            ;;
        restart)
            stop_services
            start_all_services
            ;;
        logs)
            show_logs
            ;;
        clean)
            clean_output
            ;;
        test)
            run_smoke_tests
            ;;
        maintenance)
            enable_maintenance
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
