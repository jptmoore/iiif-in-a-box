#!/bin/bash
# IIIF-In-A-Box Bootstrap Script v2
# Uses Miiify v2 with separate input/output directories
set -e

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

# Default configuration
DEFAULT_OUTPUT_DIR="./output"
DEFAULT_HOSTNAME="http://localhost:8080"
DOCKER_COMPOSE_CMD="docker compose"

# Source helper scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/config-helpers.sh"
source "${SCRIPT_DIR}/scripts/miiify-helpers.sh"
source "${SCRIPT_DIR}/scripts/image-helpers.sh"
source "${SCRIPT_DIR}/scripts/annosearch-helpers.sh"

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
                               (default: http://localhost:8080)
  --help, -h                   Show this help message

Commands:
  build                        - Build IIIF service from input directory
  status                       - Show service status
  stop                         - Stop all services
  restart                      - Restart all services
  logs                         - Show service logs
  clean                        - Stop services and clean output directory
  maintenance                  - Enable maintenance mode (stops services, shows maintenance page)

Examples:
  # Build from input directory (first time)
  $0 build --input-dir /home/john/git/domesday-in-a-box
  
  # Build with custom output directory
  $0 build -i /home/john/git/domesday-in-a-box -o /home/john/iiif-output
  
  # Build for deployment with external hostname
  $0 build -i ~/domesday-in-a-box --hostname http://192.168.1.100:8080
  
  # Check service status
  $0 status
  
  # View logs
  $0 logs
  
  # Stop all services
  $0 stop
  
  # Clean everything (stop services, remove output)
  $0 clean

Input Directory Structure:
  <input-dir>/
  ├── config.yml          # Project configuration (required)
  ├── images/             # Source images (optional)
  │   ├── image1.jpg
  │   └── image2.jpg
  └── annotations/        # W3C Web Annotations (optional)
      ├── canvas-1/
      │   ├── annotation-1.json
      │   └── annotation-2.json
      └── canvas-2/
          └── annotation-3.json

Output Directory Structure:
  <output-dir>/
  ├── miiify/
  │   ├── git_store/      # Miiify git storage
  │   └── pack_store/     # Miiify pack storage (served)
  ├── web/
  │   ├── iiif/           # Generated IIIF manifests
  │   ├── pages/          # Generated HTML pages
  │   └── images/         # Processed images
  └── logs/               # Service logs

EOF
}

# Function to parse command line arguments
parse_arguments() {
    INPUT_DIR=""
    OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
    HOSTNAME="$DEFAULT_HOSTNAME"
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
            --help|-h)
                show_help
                exit 0
                ;;
            build|status|stop|restart|logs|clean|maintenance)
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

# Function to generate IIIF manifest for a project
generate_manifest() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    
    log_info "Generating IIIF manifest for project: $project_name"
    
    mkdir -p "${OUTPUT_DIR}/web/iiif"
    local manifest_path="${OUTPUT_DIR}/web/iiif/${project_name}.json"
    
    # Create a IIIF Collection manifest that points to the Miiify pack store
    cat > "$manifest_path" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${project_name}.json",
  "type": "Collection",
  "label": {
    "en": ["${project_title}"]
  },
  "summary": {
    "en": ["${project_description}"]
  },
  "items": [
    {
      "id": "${hostname}/miiify/",
      "type": "Collection",
      "label": {
        "en": ["Annotations"]
      }
    }
  ],
  "seeAlso": [
    {
      "id": "${hostname}/miiify/",
      "type": "Dataset",
      "label": {
        "en": ["View all annotations"]
      },
      "format": "application/ld+json;profile=\"http://www.w3.org/ns/anno.jsonld\""
    }
  ],
  "service": [
    {
      "id": "${hostname}/annosearch/${project_name}/search",
      "type": "SearchService1",
      "label": "Search within this collection"
    }
  ]
}
EOF
    
    log_success "Generated manifest: ${manifest_path}"
}

# Function to generate HTML viewer page from template
generate_viewer_page() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    
    log_info "Generating viewer page for project: $project_name"
    
    mkdir -p "${OUTPUT_DIR}/web/pages"
    local page_path="${OUTPUT_DIR}/web/pages/${project_name}.html"
    local template_path="templates/pages/_template.html"
    
    if [ ! -f "$template_path" ]; then
        log_error "Template not found: $template_path"
        return 1
    fi
    
    # Replace placeholders in template
    sed -e "s/Demo/${project_title}/g" \
        -e "s/demo/${project_name}/g" \
        -e "s|https://digitaldomesday.org|${hostname}|g" \
        "$template_path" > "$page_path"
    
    log_success "Generated viewer page: ${page_path}"
    log_info "View at: ${hostname}/pages/${project_name}.html"
}

# Function to setup web content
setup_web_content() {
    log_info "Setting up web content..."
    
    # Copy static template files to output
    cp templates/index.html "${OUTPUT_DIR}/web/"
    cp templates/maintenance.html "${OUTPUT_DIR}/web/"
    
    log_success "Web content setup complete"
}

# Function to create docker network
create_docker_network() {
    if ! docker network ls | grep -q "iiif-network"; then
        log_info "Creating shared Docker network..."
        docker network create iiif-network
        log_success "Docker network created"
    else
        log_info "Docker network already exists"
    fi
}

# AnnoSearch functions are now in scripts/annosearch-helpers.sh

# Function to build project
build_project() {
    log_info "============================================"
    log_info "IIIF-in-a-Box Build Process"
    log_info "============================================"
    log_info "Input Directory:  $INPUT_DIR"
    log_info "Output Directory: $OUTPUT_DIR"
    log_info "Hostname:         $HOSTNAME"
    log_info "============================================"
    
    # Step 0: Stop any running services to avoid lock file issues
    log_info "Stopping any running services (including maintenance mode)..."
    stop_services
    
    # Also stop maintenance mode if it's running
    docker compose -f nginx/docker-compose.maintenance.yml down 2>/dev/null || true
    
    # Step 1: Validate input directory
    if ! validate_input_directory "$INPUT_DIR"; then
        log_error "Input directory validation failed"
        exit 1
    fi
    
    # Step 2: Read configuration
    if ! read_project_config "$INPUT_DIR"; then
        log_error "Failed to read project configuration"
        exit 1
    fi
    
    log_info "============================================"
    log_info "Project: $PROJECT_NAME"
    log_info "Title: $PROJECT_TITLE"
    log_info "============================================"
    
    # Step 3: Create output directory structure
    log_info "Creating output directory structure..."
    mkdir -p "$OUTPUT_DIR"/{miiify/{git_store,pack_store},web/{iiif,pages,images},annosearch/qwdata,logs}
    
    # Step 4: Process images
    if ! process_images "$INPUT_DIR" "$OUTPUT_DIR" "$PROJECT_NAME"; then
        log_error "Image processing failed"
        exit 1
    fi
    
    # Step 5: Run Miiify workflow (import → compile)
    if ! miiify_full_workflow "$INPUT_DIR" "$OUTPUT_DIR" "$HOSTNAME"; then
        log_error "Miiify workflow failed"
        exit 1
    fi
    
    # Step 6: Generate IIIF manifests
    if ! generate_manifest "$PROJECT_NAME" "$PROJECT_TITLE" "$PROJECT_DESCRIPTION" "$HOSTNAME"; then
        log_error "Manifest generation failed"
        exit 1
    fi
    
    # Step 7: Generate HTML viewer pages
    if ! generate_viewer_page "$PROJECT_NAME" "$PROJECT_TITLE" "$PROJECT_DESCRIPTION" "$HOSTNAME"; then
        log_error "Page generation failed"
        exit 1
    fi
    
    # Step 8: Setup web content
    setup_web_content
    
    # Step 9: Create Docker network
    create_docker_network
    
    # Step 10: Start all services
    if ! start_all_services; then
        log_error "Failed to start all services"
        exit 1
    fi
    
    # Step 11: Wait for AnnoSearch to be ready
    if ! wait_for_annosearch; then
        log_warning "AnnoSearch not ready, skipping search indexing"
    else
        # Step 12: Create search index and load data
        if create_annosearch_index "$PROJECT_NAME"; then
            load_annosearch_data "$PROJECT_NAME" "$HOSTNAME" || log_warning "Failed to load data into AnnoSearch"
        fi
    fi
    
    log_info "============================================"
    log_success "Build completed successfully!"
    log_info "============================================"
    log_info "Services:"
    log_info "  - Viewer:      ${HOSTNAME}/pages/${PROJECT_NAME}.html"
    log_info "  - Manifests:   ${HOSTNAME}/iiif/"
    log_info "  - Images:      ${HOSTNAME}/iiif/image/"
    log_info "  - Annotations: ${HOSTNAME}/miiify/"
    log_info "  - Search:      ${HOSTNAME}/annosearch/"
    log_info "============================================"
}

# Function to start all services
start_all_services() {
    log_info "Starting all IIIF services..."
    
    # Export environment variables for docker-compose
    export OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
    export PROJECT_NAME
    export MIIIFY_BASE_URL="${HOSTNAME}/miiify"
    export ANNOSEARCH_PUBLIC_URL="${HOSTNAME}/annosearch"
    
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Miiify base URL: $MIIIFY_BASE_URL"
    
    # Start all services using main docker-compose.yml
    log_info "Starting IIIF-in-a-Box services..."
    $DOCKER_COMPOSE_CMD up -d
    
    if [ $? -ne 0 ]; then
        log_error "Failed to start services"
        return 1
    fi
    
    log_success "All services started"
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 8
    
    # Show service status
    log_info "Service status:"
    $DOCKER_COMPOSE_CMD ps
    
    return 0
}

# Function to show status
show_status() {
    log_info "Service Status:"
    log_info "============================================"
    $DOCKER_COMPOSE_CMD ps
    log_info "============================================"
    
    # Check individual services
    for service in iipimage quickwit annosearch miiify nginx; do
        if docker ps --format '{{.Names}}' | grep -q "iiif-${service}"; then
            log_success "${service}: Running"
        else
            log_warning "${service}: Not running"
        fi
    done
    
    log_info "============================================"
}

# Function to stop services
stop_services() {
    log_info "Stopping all services..."
    
    # Stop main docker-compose services
    $DOCKER_COMPOSE_CMD down 2>/dev/null || true
    
    log_success "Services stopped"
}

# Function to show logs
show_logs() {
    log_info "Showing service logs (Ctrl+C to exit)..."
    $DOCKER_COMPOSE_CMD logs -f
}

# Function to clean output
clean_output() {
    log_warning "This will stop all services and remove the output directory"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        stop_services
        
        if [ -d "$OUTPUT_DIR" ]; then
            log_info "Removing output directory: $OUTPUT_DIR"
            rm -rf "$OUTPUT_DIR"
            log_success "Output directory removed"
        fi
    else
        log_info "Clean cancelled"
    fi
}

# Function to enable maintenance mode
enable_maintenance() {
    log_warning "Enabling maintenance mode..."
    log_info "This will stop all services and show a maintenance page"
    
    # Stop all services
    stop_services
    
    # Start maintenance mode using nginx/docker-compose.maintenance.yml
    log_info "Starting maintenance mode..."
    docker compose -f nginx/docker-compose.maintenance.yml up -d
    
    if [ $? -ne 0 ]; then
        log_error "Failed to start maintenance mode"
        return 1
    fi
    
    log_success "Maintenance mode enabled"
    log_info "Maintenance page available at http://localhost:8080"
    log_info "To bring services back online, run: ./bootstrap.sh build --input-dir <path>"
    return 0
}

# Main execution
main() {
    parse_arguments "$@"
    check_dependencies
    
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
