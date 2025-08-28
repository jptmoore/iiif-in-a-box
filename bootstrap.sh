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
  --help, -h                    Show this help message

Commands:
  build            - Update projects and build/start services (default)
  build-proxy      - Build with proxy-friendly options (for corporate networks)
  update-only      - Only update git repositories
  status           - Show service status
  stop             - Stop all services
  restart          - Restart all services
  logs             - Show service logs

Examples:
  $0 --project myproject --uri https://example.com/manifest.json build
  $0 -p medieval -u https://api.example.com/collection/123 build-proxy
  $0 --project demo build

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
create_iiif_manifest_temp() {
    local project_name="$1"
    local uri="$2"
    local manifest_file="$3"
    
    log_info "Creating IIIF manifest file: $manifest_file"
    
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

# Function to create HTML page
create_html_page_temp() {
    local project_name="$1"
    local page_file="$2"
    
    log_info "Creating HTML page: $page_file"
    
    # Capitalize first letter for display
    local project_display_name="${project_name^}"
    
    cat > "$page_file" << EOF
<!DOCTYPE html>
<html lang="en" class="tna-template">
<head>
  <meta charset="UTF-8">
  <title>${project_display_name} - IIIF-in-a-Box</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Explore the ${project_display_name} collection in our interactive IIIF viewer">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Open+Sans:wght@400..700&family=Roboto+Mono:wght@400..500&display=swap">
  <style>
    /* TNA-inspired styling */
    .tna-template {
      font-family: "Open Sans", Arial, sans-serif;
      color: #26262a;
      background-color: #ffffff;
      margin: 0;
      padding: 0;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }

    .tna-template * {
      box-sizing: border-box;
    }

    /* Header styling inspired by TNA */
    .tna-header {
      background-color: #010101;
      color: #ffffff;
      padding: 1rem 0;
      border-bottom: 4px solid #fe1d57;
    }

    .tna-container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 0 1rem;
    }

    .tna-header__content {
      display: flex;
      justify-content: flex-start;
      align-items: center;
    }

    .tna-header__logo {
      height: 40px;
      width: auto;
    }

    /* Navigation breadcrumbs */
    .tna-breadcrumbs {
      background-color: #f4f4f4;
      padding: 0.75rem 0;
      border-bottom: 1px solid #d9d9d6;
    }

    .tna-breadcrumbs__list {
      list-style: none;
      margin: 0;
      padding: 0;
      display: flex;
      align-items: center;
      flex-wrap: wrap;
    }

    .tna-breadcrumbs__item {
      display: flex;
      align-items: center;
    }

    .tna-breadcrumbs__item:not(:last-child)::after {
      content: "›";
      margin: 0 0.5rem;
      color: #8c9694;
    }

    .tna-breadcrumbs__link {
      color: #0062a8;
      text-decoration: underline;
      text-decoration-thickness: 2px;
      text-underline-offset: 2px;
      font-size: 0.875rem;
    }

    .tna-breadcrumbs__link:hover {
      color: #004c7e;
      text-decoration-thickness: 3px;
    }

    .tna-breadcrumbs__current {
      color: #26262a;
      font-size: 0.875rem;
    }

    /* Main content */
    .tna-section {
      flex: 1;
      padding: 2rem 0;
    }

    .tna-heading-xl {
      font-family: "Open Sans", Arial, sans-serif;
      font-size: clamp(2rem, 4vw, 3rem);
      font-weight: 700;
      line-height: 1.1;
      margin: 0 0 1.5rem 0;
      color: #26262a;
    }

    .tna-chip {
      display: inline-block;
      background-color: #fe1d57;
      color: #ffffff;
      padding: 0.25rem 0.75rem;
      border-radius: 0.25rem;
      font-size: 0.875rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.025em;
      margin-bottom: 0.75rem;
    }

    .tna-large-paragraph {
      font-size: 1.25rem;
      line-height: 1.4;
      color: #26262a;
      margin-bottom: 2rem;
      max-width: 40rem;
    }

    /* Viewer container */
    .tna-viewer-container {
      border: 1px solid #d9d9d6;
      border-radius: 0.5rem;
      overflow: hidden;
      background-color: #ffffff;
      box-shadow: 0 2px 8px rgba(38, 38, 42, 0.1);
    }

    .tna-viewer-container iframe {
      width: 100%;
      height: 70vh;
      min-height: 500px;
      border: none;
      display: block;
    }

    /* Grid system */
    .tna-column {
      width: 100%;
    }

    .tna-column--width-2-3 {
      width: 66.6667%;
    }

    .tna-column--width-5-6-medium {
      width: 83.3333%;
    }

    @media (max-width: 768px) {
      .tna-header__content {
        justify-content: flex-start;
      }

      .tna-heading-xl {
        font-size: 2rem;
      }
      
      .tna-large-paragraph {
        font-size: 1.125rem;
      }

      .tna-viewer-container iframe {
        height: 60vh;
        min-height: 400px;
      }
    }

    /* Footer */
    .tna-footer {
      background-color: #26262a;
      color: #ffffff;
      padding: 1rem 0;
      margin-top: auto;
    }

    .tna-footer__content {
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 1rem;
    }

    .tna-footer__text {
      font-size: 0.875rem;
      color: #d9d9d6;
    }

    .tna-footer__links {
      display: flex;
      gap: 1.5rem;
      list-style: none;
      margin: 0;
      padding: 0;
    }

    .tna-footer__link {
      color: #ffffff;
      text-decoration: underline;
      text-decoration-thickness: 1px;
      text-underline-offset: 2px;
      font-size: 0.875rem;
    }

    .tna-footer__link:hover {
      text-decoration-thickness: 2px;
    }

    @media (max-width: 768px) {
      .tna-footer__content {
        flex-direction: column;
        align-items: flex-start;
      }

      .tna-footer__links {
        flex-wrap: wrap;
      }
    }
  </style>
</head>
<body class="tna-template__body">
  <header class="tna-header">
    <div class="tna-container">
      <div class="tna-header__content">
        <img src="/assets/tna-square-logo.svg" 
             alt="IIIF-in-a-Box" 
             class="tna-header__logo">
      </div>
    </div>
  </header>

  <nav class="tna-breadcrumbs">
    <div class="tna-container">
      <ol class="tna-breadcrumbs__list">
        <li class="tna-breadcrumbs__item">
          <a href="/" class="tna-breadcrumbs__link">Home</a>
        </li>
        <li class="tna-breadcrumbs__item">
          <a href="/pages/" class="tna-breadcrumbs__link">Collections</a>
        </li>
        <li class="tna-breadcrumbs__item">
          <span class="tna-breadcrumbs__current">${project_display_name}</span>
        </li>
      </ol>
    </div>
  </nav>

  <main id="main-content" class="tna-section">
    <div class="tna-container">
      <div class="tna-column">
        <div class="tna-chip">IIIF Collection</div>
        <h1 class="tna-heading-xl">${project_display_name}</h1>
        <p class="tna-large-paragraph">
          Explore the ${project_display_name} collection using our interactive IIIF viewer. 
          Navigate through the digital materials and examine them in detail.
        </p>
        
        <div class="tna-viewer-container">
          <iframe
            src="/viewer/?iiif-content=http://localhost:8080/iiif/${project_name}.json"
            allowfullscreen
            allow="clipboard-write; clipboard-read"
            title="IIIF Viewer showing the ${project_display_name} collection"
          ></iframe>
        </div>
      </div>
    </div>
  </main>

  <footer class="tna-footer">
    <div class="tna-container">
      <div class="tna-footer__content">
        <div class="tna-footer__text">
          Powered by IIIF-in-a-Box
        </div>
        <ul class="tna-footer__links">
          <li><a href="/accessibility/" class="tna-footer__link">Accessibility</a></li>
          <li><a href="/cookies/" class="tna-footer__link">Cookies</a></li>
          <li><a href="/" class="tna-footer__link">Home</a></li>
        </ul>
      </div>
    </div>
  </footer>
</body>
</html>
EOF
    
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
    
    # Create temporary files first
    local temp_dir=$(mktemp -d)
    local temp_manifest="$temp_dir/${project_name}.json"
    local temp_page="$temp_dir/${project_name}.html"
    
    # Create IIIF manifest in temp location
    if ! create_iiif_manifest_temp "$project_name" "$uri" "$temp_manifest"; then
        log_error "Failed to create IIIF manifest"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Create HTML page in temp location  
    if ! create_html_page_temp "$project_name" "$temp_page"; then
        log_error "Failed to create HTML page"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Copy files to web directory structure
    log_info "Copying project files to web directory..."
    
    # Ensure web directories exist
    mkdir -p "web/iiif"
    mkdir -p "web/pages"
    
    # Copy files
    cp "$temp_manifest" "web/iiif/${project_name}.json"
    cp "$temp_page" "web/pages/${project_name}.html"
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    
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
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
