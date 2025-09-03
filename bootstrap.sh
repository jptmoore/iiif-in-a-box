#!/bin/bash
# IIIF-In-A-Box Bootstrap Script
set -e

# Configuration - clone to parent directory
PROJECTS=(
    "../tamerlane:https://github.com/jptmoore/tamerlane.git"
    "../miiify:https://github.com/jptmoore/miiify.git" 
    "../annosearch:https://github.com/jptmoore/annosearch.git"
)

# Default configuration
DEFAULT_PROJECT_NAME="demo"
DEFAULT_COLLECTION_DIR=""

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

# Function to parse command line arguments
parse_arguments() {
    PROJECT_NAME="$DEFAULT_PROJECT_NAME"
    COLLECTION_DIR="$DEFAULT_COLLECTION_DIR"
    FORCE_REBUILD="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project|-p)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --collection|-c)
                COLLECTION_DIR="$2"
                shift 2
                ;;
            --force|-f)
                FORCE_REBUILD="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            stop|status|restart|logs)
                # Commands that don't require project setup
                BOOTSTRAP_COMMAND="$1"
                shift
                ;;
            *)
                # Store command for later use
                BOOTSTRAP_COMMAND="$1"
                shift
                # Check if this is a project name for build command
                if [ "$BOOTSTRAP_COMMAND" = "build" ] && [ -n "$1" ]; then
                    PROJECT_NAME="$1"
                    shift
                fi
                ;;
        esac
    done
    
    # Set default command if none provided
    if [ -z "$BOOTSTRAP_COMMAND" ]; then
        BOOTSTRAP_COMMAND="build"
    fi
}

# Function to show help
show_help() {
    cat << EOF
IIIF-In-A-Box Bootstrap Script

Usage: $0 [OPTIONS] [COMMAND] [PROJECT_NAME]

Options:
  --project, -p PROJECT_NAME        Name of the project (required for build)
  --collection, -c COLLECTION_DIR   Directory containing IIIF resources 
                                    (optional - defaults to project name)
                                    Searches: ./{project}, ../{project}, ../../{project}
  --force, -f                       Force rebuild all Docker images (including slow Cantaloupe)
  --help, -h                        Show this help message

Commands:
  build [PROJECT_NAME]     - Build IIIF service from web/ directory content
  update-only              - Only update git repositories
  status                   - Show service status
  stop                     - Stop all services
  restart                  - Restart all services
  logs                     - Show service logs

Examples:
  # Build with your content (fast - reuses existing images)
  $0 build my-project
  
  # Force complete rebuild (slow - rebuilds everything including Cantaloupe)
  $0 build my-project --force
  
  # Build demo project
  $0 build
  $0 -p newspapers -c ../newspaper-collection build

Collection Directory Structure:
  The collection directory should contain:
    manifests/       - IIIF manifest/collection files (.json)
    images/          - Image files (served via Cantaloupe IIIF Image API)
    annotations/     - Annotation files (.json)

  Example layout:
    ../your-iiif-collection/
    ├── manifests/
    │   ├── collection.json
    │   └── manifest1.json
    ├── images/
    │   ├── page001.jpg
    │   └── page002.jpg
    └── annotations/
        └── annotations.json

  The system will:
    - Look for {project-name}.json in manifests/ or use the first manifest found
    - Serve images via Cantaloupe at http://localhost:8080/cantaloupe/
    - Make annotations available at http://localhost:8080/annotations/
    - Create a viewer at http://localhost:8080/pages/{project-name}.html

EOF
}

# Function to validate project name
validate_project_name() {
    local name="$1"
    
    if [ -z "$name" ]; then
        log_error "Project name cannot be empty"
        return 1
    fi
    
    # Check for valid characters (alphanumeric, hyphens, underscores)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Project name must contain only alphanumeric characters, hyphens, and underscores"
        return 1
    fi
    
    return 0
}

# Function to setup project from filesystem directory
setup_project_from_directory() {
    local project_name="$1"
    local collection_dir="$2"
    
    log_info "Setting up project from directory: $collection_dir"
    
    # Collection directory defaults to project name if not provided
    if [ -z "$collection_dir" ]; then
        collection_dir="$project_name"
        log_info "Using project name as collection directory: $collection_dir"
    fi
    
    # If it's not an absolute path, try to find the project directory in common locations
    if [[ "$collection_dir" != /* ]]; then
        # List of possible locations to search for the project directory
        possible_paths=(
            "$(pwd)/$collection_dir"           # Current directory (iiif-in-a-box)
            "$(pwd)/../$collection_dir"        # Parent directory (git level)
            "$(pwd)/../../$collection_dir"     # Grandparent directory
            "$collection_dir"                  # Relative to current location
        )
        
        found_path=""
        for path in "${possible_paths[@]}"; do
            if [ -d "$path" ]; then
                found_path="$path"
                log_info "Found collection directory at: $found_path"
                break
            fi
        done
        
        if [ -n "$found_path" ]; then
            collection_dir="$found_path"
        else
            # If not found, resolve to absolute path anyway for better error message
            collection_dir="$(pwd)/$collection_dir"
        fi
    fi
    
    # Check if directory exists
    if [ ! -d "$collection_dir" ]; then
        log_error "Collection directory does not exist: $collection_dir"
        log_error "Searched in the following locations:"
        if [[ "$collection_dir" != /* ]]; then
            # This shouldn't happen now, but just in case
            log_error "  - $(pwd)/$collection_dir"
            log_error "  - $(pwd)/../$collection_dir"
        else
            log_error "  - $collection_dir"
            log_error "  - $(dirname "$collection_dir")/../$(basename "$collection_dir")"
        fi
        log_error "Please ensure the project directory exists or use --collection to specify the correct path."
        return 1
    fi
    
    # Create target directories
    mkdir -p "web/iiif" "web/images" "web/annotations"
    
    # Copy manifests if they exist
    if [ -d "$collection_dir/manifests" ]; then
        log_info "Copying IIIF manifests..."
        find "$collection_dir/manifests" -name "*.json" -exec cp {} "web/iiif/" \;
        
        # If there's a manifest with the project name, use it as the main manifest
        if [ -f "$collection_dir/manifests/${project_name}.json" ]; then
            log_info "Using ${project_name}.json as main manifest"
        elif [ -f "web/iiif/${project_name}.json" ]; then
            log_info "Found ${project_name}.json in manifests"
        else
            # Use the first manifest found and rename it
            first_manifest=$(find "web/iiif" -name "*.json" | head -1)
            if [ -n "$first_manifest" ]; then
                cp "$first_manifest" "web/iiif/${project_name}.json"
                log_info "Using $(basename "$first_manifest") as main manifest for ${project_name}"
            fi
        fi
    else
        log_error "No manifests directory found in collection directory. Directory must contain a 'manifests/' subdirectory."
        return 1
    fi
    
    # Copy images if they exist
    if [ -d "$collection_dir/images" ]; then
        log_info "Copying images..."
        cp -r "$collection_dir/images"/* "web/images/" 2>/dev/null || log_warning "No images found or failed to copy images"
    else
        log_warning "No images directory found in collection directory"
    fi
    
    # Copy annotations if they exist
    if [ -d "$collection_dir/annotations" ]; then
        log_info "Copying annotations..."
        cp -r "$collection_dir/annotations"/* "web/annotations/" 2>/dev/null || log_warning "No annotations found or failed to copy annotations"
    else
        log_warning "No annotations directory found in collection directory"
    fi
    
    # Ensure we have a main manifest
    if [ ! -f "web/iiif/${project_name}.json" ]; then
        log_error "No suitable manifest found for project ${project_name}. Expected manifests/${project_name}.json or any .json file in manifests/"
        return 1
    fi
    
    log_success "Project setup from directory completed"
}

# Function to load annotations into miiify annotation server
load_annotations_to_miiify() {
    local project_name="$1"
    
    log_info "Checking for annotations to load into miiify..."
    
    # Check if there are annotation files
    if [ ! -d "web/annotations" ] || [ -z "$(ls -A web/annotations 2>/dev/null)" ]; then
        log_info "No annotations found to load"
        return 0
    fi
    
    # Look for annotation files (JSON format)
    local annotation_files=$(find web/annotations -name "*.json" | head -1)
    
    if [ -z "$annotation_files" ]; then
        log_info "No JSON annotation files found in web/annotations"
        return 0
    fi
    
    log_info "Found annotation files. Loading into miiify annotation server..."
    
    # Ensure miiify database directory exists
    mkdir -p "miiify/db"
    
    # Copy the annotation file to miiify directory for processing
    local annotation_file=$(echo "$annotation_files" | head -1)
    cp "$annotation_file" "miiify/${project_name}-annotations.json"
    
    # Wait for miiify service to be ready
    log_info "Waiting for miiify service to be ready..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if curl -s -f --noproxy '*' --max-time 5 "http://localhost:10000/" > /dev/null 2>&1; then
            log_info "Miiify service is ready"
            break
        fi
        sleep 2
        retries=$((retries - 1))
    done
    
    if [ $retries -eq 0 ]; then
        log_error "Miiify service did not become ready within timeout"
        return 1
    fi
    
    # Create a project-specific load script
    cd miiify
    
    # Run the annotation loading with project name as argument
    log_info "Loading annotations using ts-node..."
    if npx ts-node load.ts "$project_name"; then
        log_success "Annotations loaded successfully into miiify"
        log_info "Updated manifest with annotation references in both project and web directories"
    else
        log_error "Failed to load annotations into miiify"
        cd - > /dev/null
        return 1
    fi
    
    # Clean up temporary files (no longer needed since load.ts writes directly to correct locations)
    rm -f "${project_name}-annotations.json"
    cd - > /dev/null
    log_success "Annotation loading completed"
}

load_annotations_from_web() {
    local project_name="$1"
    
    log_info "Loading annotations from web/annotations/ directory..."
    
    # Check if annotations directory exists and has files
    if [ ! -d "web/annotations" ] || [ -z "$(ls -A web/annotations 2>/dev/null)" ]; then
        log_warning "No annotations found in web/annotations/ directory"
        return 1
    fi
    
    # Find annotation files
    local annotation_files
    annotation_files=$(find "web/annotations" -name "*.json" -type f)
    
    if [ -z "$annotation_files" ]; then
        log_warning "No JSON annotation files found in web/annotations/"
        return 1
    fi
    
    log_info "Found annotation files: $(echo "$annotation_files" | wc -l) files"
    log_info "Load script will read directly from web/annotations/ directory"
    
    # Ensure miiify database directory exists
    mkdir -p "miiify/db"
    
    # Wait for miiify service to be ready
    log_info "Waiting for miiify service to be ready..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if curl -s -f --noproxy '*' --max-time 5 "http://localhost:10000/" > /dev/null 2>&1; then
            log_info "Miiify service is ready"
            break
        fi
        sleep 2
        retries=$((retries - 1))
    done
    
    if [ $retries -eq 0 ]; then
        log_error "Miiify service did not become ready within timeout"
        return 1
    fi
    
    # Run annotation loading - load.ts will read directly from web/annotations/
    cd miiify
    
    log_info "Loading annotations using ts-node..."
    if npx ts-node load.ts "$project_name"; then
        log_success "Annotations loaded successfully into miiify"
        log_info "Generated manifest with annotation references in web/iiif/"
        cd - > /dev/null
        return 0
    else
        log_error "Failed to load annotations with ts-node"
        cd - > /dev/null
        return 1
    fi
}

# Function to index annotations with annosearch
index_annotations_with_annosearch() {
    local project_name="$1"
    
    log_info "Indexing annotations for search functionality..."
    
    # Check if annosearch load script exists
    if [ ! -f "annosearch/load.sh" ]; then
        log_warning "AnnoSearch load script not found - skipping search indexing"
        return 0
    fi
    
    # Run the annosearch indexing script
    if ./annosearch/load.sh "$project_name"; then
        log_success "Annotations indexed successfully for search"
        log_info "Search API available at: http://localhost:8080/annosearch/${project_name}/search"
        return 0
    else
        log_warning "Failed to index annotations for search, but continuing..."
        return 0  # Don't fail the build if search indexing fails
    fi
}

# Function to create HTML page from template
create_html_page() {
    local project_name="$1"
    local template_file="web/pages/demo.html"
    local page_file="web/pages/${project_name}.html"
    
    log_info "Creating HTML page: $page_file"
    
    # Create directory if it doesn't exist
    mkdir -p "web/pages"
    
    # Check if template exists
    if [ ! -f "$template_file" ]; then
        log_error "Template file not found: $template_file"
        return 1
    fi
    
    # Copy template and replace project-specific content
    # Capitalize first letter for display
    local project_display_name="${project_name^}"
    
    cp "$template_file" "$page_file"
    
    # Replace project-specific content in the copied file
    sed -i "s/demo\.json/${project_name}.json/g" "$page_file"
    sed -i "s/Demo/${project_display_name}/g" "$page_file"
    sed -i "s/demo/${project_name}/g" "$page_file"
    
    log_success "HTML page created: $page_file"
}

# Function to setup project files
setup_project_files() {
    local project_name="$PROJECT_NAME"
    local collection_dir="$COLLECTION_DIR"
    
    log_info "Setting up project files for: $project_name"
    
    # Validate project name
    if ! validate_project_name "$project_name"; then
        return 1
    fi
    
    # If no collection directory specified, use project name as directory name
    if [ -z "$collection_dir" ]; then
        collection_dir="$project_name"
        log_info "No collection directory specified, using project name: $collection_dir"
    fi
    
    # Setup from filesystem directory (required)
    if ! setup_project_from_directory "$project_name" "$collection_dir"; then
        log_error "Failed to setup project from directory"
        return 1
    fi
    
    # Create HTML page from template
    if ! create_html_page "$project_name"; then
        log_error "Failed to create HTML page"
        return 1
    fi
    
    log_success "Project files created successfully for: $project_name"
    log_info "Collection Directory: $collection_dir"
    log_info "IIIF Manifest: web/iiif/${project_name}.json"
    log_info "HTML Page: web/pages/${project_name}.html"
    log_info "Viewer URL: http://localhost:8080/pages/${project_name}.html"
    log_info "Images served via: http://localhost:8080/cantaloupe/"
    log_info "Annotations available at: http://localhost:8080/annotations/"
}

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

# Function to rebuild web service after project file changes
rebuild_web_service() {
    local compose_file="docker-compose.yml"
    
    log_info "Rebuilding web service to include project files using $compose_file..."
    
    cd proxy
    
    # Stop web service if running
    if docker-compose -f "$compose_file" ps web 2>/dev/null | grep -q "Up"; then
        log_info "Stopping web service..."
        docker-compose -f "$compose_file" stop web
    fi
    
    # Rebuild only the web service
    log_info "Building web service..."
    docker-compose -f "$compose_file" build --no-cache web
    
    # Start web service
    log_info "Starting web service..."
    docker-compose -f "$compose_file" up -d web
    
    cd - > /dev/null
    
    log_success "Web service rebuilt with updated project files"
}

# Function to build and start services
build_and_start() {
    local compose_file="docker-compose.yml"
    
    log_info "Building and starting services using $compose_file..."
    
    cd proxy
    
    # Stop any running services
    if docker-compose -f "$compose_file" ps 2>/dev/null | grep -q "Up"; then
        log_info "Stopping existing services..."
        docker-compose -f "$compose_file" down
    fi
    
    # Build services
    log_info "Building Docker services..."
    docker-compose -f "$compose_file" build --no-cache
    
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

build_core_services() {
    local compose_file="docker-compose.yml"
    
    log_info "Building core services (annotation processing and search infrastructure)..."
    
    cd proxy
    
    # Stop any running services
    if docker-compose -f "$compose_file" ps 2>/dev/null | grep -q "Up"; then
        log_info "Stopping existing services..."
        docker-compose -f "$compose_file" down
    fi
    
    # Build and start services needed for annotation processing and search
    log_info "Building annotation and search services..."
    build_service_if_needed "$compose_file" "quickwit" "$FORCE_REBUILD"
    build_service_if_needed "$compose_file" "annosearch" "$FORCE_REBUILD"
    build_service_if_needed "$compose_file" "miiify" "$FORCE_REBUILD"
    
    log_info "Starting annotation and search services..."
    docker-compose -f "$compose_file" up -d quickwit annosearch miiify
    
    # Wait for services to be ready
    log_info "Waiting for annotation and search services to be ready..."
    sleep 10
    
    log_success "Annotation processing and search infrastructure ready!"
    
    cd - > /dev/null
}

build_web_service() {
    local compose_file="docker-compose.yml"
    
    log_info "Building complete IIIF service with all content..."
    log_info "📋 Content includes: manifests (from annotations) + images + static files + viewer"
    
    cd proxy
    
    # Build all services, checking for existing images to speed up builds
    log_info "Building all services (using cached images where possible)..."
    if [ "$FORCE_REBUILD" = "true" ]; then
        log_info "🔄 Force rebuild requested - rebuilding all images from scratch"
    fi
    build_services_optimized "$compose_file" "$FORCE_REBUILD"
    
    # Start the complete service stack
    log_info "Starting complete IIIF service stack..."
    docker-compose -f "$compose_file" up -d
    
    # Wait for all services to be ready
    log_info "Waiting for all services to be ready..."
    sleep 10
    
    # Check service status
    if docker-compose ps | grep -q "Exit"; then
        log_error "Some services failed to start!"
        docker-compose logs
        cd - > /dev/null
        return 1
    fi
    
    log_success "🎉 Complete IIIF service is running!"
    log_info "📚 IIIF-In-A-Box is available at: http://localhost:8080"
    log_info "👁️  Tamerlane viewer at: http://localhost:8080/viewer/"
    log_info "🖼️  Images served via Cantaloupe image server"
    log_info "📝 Annotations served via Miiify annotation server"
    
    cd - > /dev/null
}

# Helper function to check if a Docker image exists locally
image_exists() {
    local image_name="$1"
    docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^${image_name}$"
}

# Helper function to build a service only if needed
build_service_if_needed() {
    local compose_file="$1"
    local service="$2"
    local force_rebuild="${3:-false}"
    
    # Get the image name for this service
    local image_name=$(docker-compose -f "$compose_file" config | grep -A 5 "^  ${service}:" | grep "image:" | awk '{print $2}' | head -1)
    
    # If no explicit image name, it will be built with a default name
    if [ -z "$image_name" ]; then
        image_name="${PWD##*/}-${service}"
    fi
    
    if [ "$force_rebuild" = "true" ] || ! image_exists "$image_name"; then
        log_info "Building $service (image: $image_name)..."
        docker-compose -f "$compose_file" build --no-cache "$service"
    else
        log_info "Using existing $service image (image: $image_name) ✓"
        # Still run build without --no-cache to update if Dockerfile changed
        docker-compose -f "$compose_file" build "$service"
    fi
}

# Helper function to build services with optimization
build_services_optimized() {
    local compose_file="$1"
    local force_rebuild="${2:-false}"
    
    # List of services that should be built
    local services=("quickwit" "annosearch" "cantaloupe" "miiify" "web" "nginx")
    
    for service in "${services[@]}"; do
        # Special handling for cantaloupe (the slow one)
        if [ "$service" = "cantaloupe" ]; then
            local cantaloupe_image="cantaloupe:5.0.7"
            if [ "$force_rebuild" != "true" ] && image_exists "$cantaloupe_image"; then
                log_info "Using existing Cantaloupe image (cantaloupe:5.0.7) ✓ - skipping slow rebuild"
            else
                log_info "Building Cantaloupe (this may take a while due to JAR download)..."
                docker-compose -f "$compose_file" build --no-cache cantaloupe
            fi
        else
            build_service_if_needed "$compose_file" "$service" "$force_rebuild"
        fi
    done
}

# Function to show service status
show_status() {
    log_info "Service Status:"
    cd proxy
    docker-compose ps
    cd - > /dev/null
}

# Main execution
main() {
    log_info "IIIF-In-A-Box Bootstrap Script"
    log_info "=============================="
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check dependencies
    check_dependencies
    
    # Setup project files (skip for service management commands)
    case "$BOOTSTRAP_COMMAND" in
        "stop"|"status"|"restart"|"logs")
            log_info "Service management command detected - skipping project setup"
            ;;
        *)
            setup_project_files
            ;;
    esac
    
    # Update/clone projects
    log_info "Updating project dependencies..."
    for project_info in "${PROJECTS[@]}"; do
        IFS=':' read -r project_path repo_url <<< "$project_info"
        update_project "$project_path" "$repo_url"
    done
    
    # Execute the requested command
    case "$BOOTSTRAP_COMMAND" in
        "update-only")
            log_success "Projects updated. Run './bootstrap.sh build' to build and start services."
            ;;
        "build")
            # Simple data-driven build process:
            # Users place content in web/ directory, we build from there
            log_info "🏗️  Building IIIF service from web/ directory content..."
            if [ "$FORCE_REBUILD" = "true" ]; then
                log_info "🔄 Force rebuild mode enabled - will rebuild all images including Cantaloupe"
            else
                log_info "⚡ Fast build mode - will reuse existing Docker images where possible"
            fi
            log_info "📋 Required content:"
            log_info "   - web/images/ (your images)"
            log_info "   - web/annotations/ (your annotations - required for manifest generation)"
            
            # Check if we have images
            if [ ! -d "web/images" ] || [ -z "$(ls -A web/images 2>/dev/null)" ]; then
                log_warning "No images found in web/images/ - using demo content"
                PROJECT_NAME="demo"
            fi
            
            # Check if we have annotations (required for manifest generation)
            if [ -n "$PROJECT_NAME" ] && [ "$PROJECT_NAME" != "demo" ]; then
                if [ ! -d "web/annotations" ] || [ -z "$(ls -A web/annotations 2>/dev/null)" ]; then
                    log_error "No annotations found in web/annotations/ directory"
                    log_error "Annotations are required to generate IIIF manifests"
                    log_error "Please add your annotation JSON files to web/annotations/"
                    exit 1
                fi
                
                # Step 1: Process annotations to generate manifests
                build_core_services
                
                log_info "📝 Processing annotations from web/annotations/ to generate IIIF manifests..."
                if ! load_annotations_from_web "$PROJECT_NAME"; then
                    log_error "Failed to process annotations - cannot continue without manifests"
                    exit 1
                fi
                
                # Step 2: Build complete IIIF service with all content
                log_info "🏗️  Building complete IIIF service with all processed content..."
                build_web_service
                
                # Step 3: Index annotations for search functionality (after full stack is up)
                log_info "🔍 Indexing annotations for search functionality..."
                index_annotations_with_annosearch "$PROJECT_NAME"
            else
                # Demo project: simple single build with pre-existing manifests
                log_info "🎯 Building demo project with pre-existing manifests..."
                build_and_start
            fi
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
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
