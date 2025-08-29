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
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                # Store command for later use
                BOOTSTRAP_COMMAND="$1"
                shift
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

Usage: $0 [OPTIONS] [COMMAND]

Options:
  --project, -p PROJECT_NAME        Set the project name (default: demo)
  --collection, -c COLLECTION_DIR   Directory containing IIIF resources (required)
  --help, -h                        Show this help message

Commands:
  build            - Update projects and build/start services (default)
  update-only      - Only update git repositories
  status           - Show service status
  stop             - Stop all services
  restart          - Restart all services
  logs             - Show service logs

Examples:
  # Setup a medieval manuscripts collection
  $0 --project medieval --collection ../medieval-manuscripts build
  
  # Setup with short flags
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
    
    # Validate that collection directory is provided
    if [ -z "$collection_dir" ]; then
        log_error "Collection directory is required. Use --collection to specify a directory containing IIIF resources."
        return 1
    fi
    
    # Resolve relative path to absolute path
    if [[ "$collection_dir" != /* ]]; then
        collection_dir="$(pwd)/$collection_dir"
    fi
    
    # Check if directory exists
    if [ ! -d "$collection_dir" ]; then
        log_error "Collection directory does not exist: $collection_dir"
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
    
    # Setup project files
    setup_project_files
    
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
            # First build all services
            build_and_start
            # Then rebuild web service to ensure project files are included
            if [ -n "$PROJECT_NAME" ] && [ "$PROJECT_NAME" != "demo" ]; then
                log_info "Project files were created/updated, rebuilding web service..."
                rebuild_web_service
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
