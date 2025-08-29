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
DEFAULT_URI=""

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
    URI="$DEFAULT_URI"
    COPY_IMAGES="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project|-p)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --uri|-u)
                URI="$2"
                shift 2
                ;;
            --copy-images)
                COPY_IMAGES="true"
                shift
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
  --project, -p PROJECT_NAME    Set the project name (default: demo)
  --uri, -u URI                 Set the IIIF manifest/collection URI
  --copy-images                 Include Cantaloupe image server for local images
  --help, -h                    Show this help message

Commands:
  build            - Update projects and build/start services (default)
  update-only      - Only update git repositories
  status           - Show service status
  stop             - Stop all services
  restart          - Restart all services
  logs             - Show service logs

Examples:
  $0 --project myproject --uri https://example.com/manifest.json build
  $0 -p medieval -u https://api.example.com/collection/123 build
  $0 --project demo --copy-images build

Note: By default, Cantaloupe image server is excluded to speed up builds.
      Use --copy-images only if you need to serve images locally.

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

# Function to create IIIF manifest file
create_iiif_manifest() {
    local project_name="$1"
    local uri="$2"
    local manifest_file="web/iiif/${project_name}.json"
    
    log_info "Creating IIIF manifest file: $manifest_file"
    
    # Create directory if it doesn't exist
    mkdir -p "web/iiif"
    
    if [ -n "$uri" ]; then
        # If URI is provided, fetch it
        log_info "Fetching IIIF resource from: $uri"
        if command -v curl &> /dev/null; then
            if curl -s -f "$uri" > "$manifest_file"; then
                log_success "IIIF resource fetched successfully"
            else
                log_error "Failed to fetch IIIF resource from $uri"
                return 1
            fi
        elif command -v wget &> /dev/null; then
            if wget -q -O "$manifest_file" "$uri"; then
                log_success "IIIF resource fetched successfully"
            else
                log_error "Failed to fetch IIIF resource from $uri"
                return 1
            fi
        else
            log_error "Neither curl nor wget available to fetch IIIF resource"
            return 1
        fi
    else
        # Create a template manifest
        log_info "Creating template manifest for project: $project_name"
        cat > "$manifest_file" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "http://localhost:8080/iiif/${project_name}.json",
  "type": "Manifest",
  "label": {
    "en": ["${project_name^} Collection"]
  },
  "service": [
    {
      "id": "http://localhost:8080/annosearch/${project_name}/search",
      "type": "SearchService2",
      "service": [
        {
          "id": "http://localhost:8080/annosearch/${project_name}/autocomplete",
          "type": "AutoCompleteService2"
        }
      ]
    }
  ],
  "metadata": [
    {
      "label": {
        "en": ["Project"]
      },
      "value": {
        "en": ["${project_name^}"]
      }
    },
    {
      "label": {
        "en": ["Type"]
      },
      "value": {
        "en": ["IIIF Collection"]
      }
    }
  ],
  "provider": [
    {
      "id": "http://localhost:8080",
      "type": "Agent",
      "label": {
        "en": ["IIIF-in-a-Box"]
      }
    }
  ],
  "items": []
}
EOF
        log_success "Template manifest created"
        log_warning "Template manifest created with empty items array. Add your canvas items to display content."
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
    local uri="$URI"
    
    log_info "Setting up project files for: $project_name"
    
    # Validate project name
    if ! validate_project_name "$project_name"; then
        return 1
    fi
    
    # Create IIIF manifest
    if ! create_iiif_manifest "$project_name" "$uri"; then
        log_error "Failed to create IIIF manifest"
        return 1
    fi
    
    # Create HTML page from template
    if ! create_html_page "$project_name"; then
        log_error "Failed to create HTML page"
        return 1
    fi
    
    log_success "Project files created successfully for: $project_name"
    log_info "IIIF Manifest: web/iiif/${project_name}.json"
    log_info "HTML Page: web/pages/${project_name}.html"
    log_info "Viewer URL: http://localhost:8080/pages/${project_name}.html"
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
    local profile_args=""
    
    # Check for copy images flag  
    if [ "$COPY_IMAGES" = "true" ]; then
        profile_args="--profile images"
    fi
    
    log_info "Rebuilding web service to include project files using $compose_file..."
    
    cd proxy
    
    # Stop web service if running
    if docker-compose -f "$compose_file" ps web 2>/dev/null | grep -q "Up"; then
        log_info "Stopping web service..."
        docker-compose -f "$compose_file" stop web
    fi
    
    # Rebuild only the web service
    log_info "Building web service..."
    docker-compose -f "$compose_file" $profile_args build --no-cache web
    
    # Start web service
    log_info "Starting web service..."
    docker-compose -f "$compose_file" $profile_args up -d web
    
    cd - > /dev/null
    
    log_success "Web service rebuilt with updated project files"
}

# Function to build and start services
build_and_start() {
    local compose_file="docker-compose.yml"
    local profile_args=""
    
    # Check for copy images flag
    if [ "$COPY_IMAGES" = "true" ]; then
        profile_args="--profile images"
        log_info "Including Cantaloupe image server (--copy-images flag set)"
    else
        log_info "Using minimal build (Cantaloupe excluded). Use --copy-images to include image server."
    fi
    
    log_info "Building and starting services using $compose_file..."
    
    cd proxy
    
    # Stop any running services
    if docker-compose -f "$compose_file" ps 2>/dev/null | grep -q "Up"; then
        log_info "Stopping existing services..."
        docker-compose -f "$compose_file" down
    fi
    
    # Build services
    log_info "Building Docker services..."
    docker-compose -f "$compose_file" $profile_args build --no-cache
    
    # Start services
    log_info "Starting services..."
    docker-compose -f "$compose_file" $profile_args up -d
    
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
