#!/bin/bash
# AnnoSearch indexing script for IIIF-In-A-Box
# This script indexes annotations from IIIF manifests served by the web server

set -e

# Configuration
PROJECT_NAME="${1:-demo}"
ANNOSEARCH_DIR="../annosearch"

# Smart URL detection - use container names if in Docker environment
if [ -f /.dockerenv ] || docker network ls 2>/dev/null | grep -q "appnet"; then
    # Running in Docker environment
    WEB_BASE_URL="http://iiif-nginx"
    ANNOSEARCH_BASE_URL="http://iiif-annosearch:3000"
else
    # Running on host
    WEB_BASE_URL="http://localhost:8080"
    ANNOSEARCH_BASE_URL="http://localhost:3000"
fi

# Colors for output  
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[ANNOSEARCH]${NC} $1"; }
log_success() { echo -e "${GREEN}[ANNOSEARCH]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[ANNOSEARCH]${NC} $1"; }
log_error() { echo -e "${RED}[ANNOSEARCH]${NC} $1"; }
log_section() { echo -e "\n${BLUE}[ANNOSEARCH]${NC} === $1 ==="; }

# Function to create/recreate index
create_index() {
    local project_name="$1"
    
    log_section "Setting up search index for project: $project_name"
    
    cd "$ANNOSEARCH_DIR"
    
    # Try to delete existing index (silently ignore errors - 404 is expected if index doesn't exist)
    log_info "Cleaning up any existing index: $project_name"
    npm start -- delete --index "$project_name" >/dev/null 2>&1
    
    # Create new index
    log_info "Creating new search index: $project_name"
    if npm start -- init --index "$project_name"; then
        log_success "Search index '$project_name' created successfully"
        return 0
    else
        log_error "Failed to create search index"
        return 1
    fi
}

# Function to load annotations from manifest URL
load_annotations() {
    local project_name="$1"
    
    log_info "Loading annotations from IIIF manifest..."
    
    cd "$ANNOSEARCH_DIR"
    
    # Construct manifest URL - use hostname from environment or default to localhost
    local base_url="${IIIF_HOSTNAME:-http://localhost:8080}"
    local manifest_url="${base_url}/iiif/${project_name}.json"
    
    log_info "Loading from manifest URL: $manifest_url"
    
    # Check if manifest exists
    if ! curl -s -f --max-time 10 "$manifest_url" > /dev/null 2>&1; then
        log_error "Manifest not found at: $manifest_url"
        log_error "Please ensure the manifest has been generated and web service is running"
        return 1
    fi
    
    # Load the manifest into annosearch
    log_info "Loading IIIF Collection into search index..."
    if npm start -- load --index "$project_name" --type Collection --uri "$manifest_url"; then
        log_success "IIIF Collection loaded successfully into search index"
        
        # Get some stats about what was loaded
        log_info "Manifest loaded from: $manifest_url"
        
        # Try to get manifest info for logging
        local manifest_info
        manifest_info=$(curl -s "$manifest_url" | jq -r '.label.en[0] // .label // "Unknown"' 2>/dev/null || echo "Unknown")
        if [ "$manifest_info" != "Unknown" ]; then
            log_info "Manifest title: $manifest_info"
        fi
        
        return 0
    else
        log_error "Failed to load IIIF Manifest from: $manifest_url"
        return 1
    fi
}

# Main function
main() {
    log_section "Starting annotation indexing for project: $PROJECT_NAME"
    
    # Check if annosearch directory exists
    if [ ! -d "$ANNOSEARCH_DIR" ]; then
        log_error "AnnoSearch directory not found: $ANNOSEARCH_DIR"
        log_error "Please ensure annosearch repository is cloned"
        exit 1
    fi

    # Create/recreate search index
    if ! create_index "$PROJECT_NAME"; then
        log_error "Failed to set up search index"
        exit 1
    fi    # Load annotations into search index
    if ! load_annotations "$PROJECT_NAME"; then
        log_error "Failed to load annotations into search index"
        exit 1
    fi
    
    log_success "🔍 Annotation indexing completed successfully!"
    log_info "📚 Search API available at: ${ANNOSEARCH_BASE_URL}/${PROJECT_NAME}/search"
    log_info "🧪 Test search: curl '${ANNOSEARCH_BASE_URL}/${PROJECT_NAME}/search?q=your-search-term'"
}

# Show help if requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << EOF
AnnoSearch Indexing Script for IIIF-In-A-Box

Usage: $0 [PROJECT_NAME]

This script indexes annotations from IIIF manifests served by the web server into
annosearch to enable full-text search across annotation content.

Arguments:
  PROJECT_NAME    Name of the project (defaults to 'demo')

Examples:
  $0 medieval-manuscripts
  $0 domesday

Requirements:
  - Full IIIF stack running (use ./bootstrap.sh to start)
  - jq command-line JSON processor

The script will:
1. Create/recreate a search index for the project
2. Load annotations from IIIF manifest served by web server
3. Make them searchable via IIIF Content Search API

Note: This script is typically called automatically by bootstrap.sh
but can be run manually after the full stack is running.

EOF
    exit 0
fi

# Run main function
main