#!/bin/bash
# AnnoSearch indexing script for IIIF-In-A-Box
# This script indexes annotations from IIIF manifests served by the web server

set -e

# Configuration
PROJECT_NAME="${1:-demo}"
ANNOSEARCH_DIR="../annosearch"
WEB_BASE_URL="http://localhost:8080"
ANNOSEARCH_BASE_URL="http://localhost:3000"

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

# Function to check if annosearch service is ready
wait_for_annosearch() {
    log_info "Waiting for annosearch service to be ready..."
    log_info "Checking annosearch at: ${ANNOSEARCH_BASE_URL}/version"
    local retries=30
    while [ $retries -gt 0 ]; do
        # Try to get version info from annosearch
        local response
        response=$(curl -s --max-time 5 "${ANNOSEARCH_BASE_URL}/version" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$response" ]; then
            log_success "AnnoSearch service is ready"
            log_info "AnnoSearch version info: $response"
            return 0
        fi
        sleep 2
        retries=$((retries - 1))
        log_info "Waiting for annosearch... ($retries retries left)"
    done
    
    log_error "AnnoSearch service did not become ready within timeout"
    log_error "Last attempt failed - check if annosearch is running on ${ANNOSEARCH_BASE_URL}"
    return 1
}

# Function to check if web service is ready
wait_for_web_service() {
    log_info "Waiting for web service to be ready..."
    log_info "Checking web service at: ${WEB_BASE_URL}/"
    local retries=30
    while [ $retries -gt 0 ]; do
        # Try to get response from web service
        local response_code
        response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${WEB_BASE_URL}/" 2>/dev/null)
        if [ $? -eq 0 ] && [ "$response_code" -ge 200 ] && [ "$response_code" -lt 400 ]; then
            log_success "Web service is ready (HTTP $response_code)"
            return 0
        fi
        sleep 2
        retries=$((retries - 1))
        log_info "Waiting for web service... ($retries retries left, last response: ${response_code:-connection failed})"
    done
    
    log_error "Web service did not become ready within timeout"
    log_error "Last attempt failed - check if web service is running on ${WEB_BASE_URL}"
    log_error ""
    log_error "Make sure the full IIIF stack is running before running this script."
    log_error "You may need to run the bootstrap script first:"
    log_error "  ./bootstrap.sh"
    log_error ""
    log_error "Or check if nginx container is running:"
    log_error "  docker ps --filter name=nginx"
    return 1
    return 1
}

# Function to create/recreate index
create_index() {
    local project_name="$1"
    
    log_section "Setting up search index for project: $project_name"
    
    cd "$ANNOSEARCH_DIR"
    
    # Try to delete existing index (check exit code to see if it existed)
    log_info "Checking for existing index: $project_name"
    if npx annosearch delete --index "$project_name" 2>/dev/null; then
        log_success "Existing index '$project_name' deleted successfully"
    else
        log_info "No existing index found for '$project_name' (or already deleted)"
    fi
    
    # Create new index
    log_info "Creating new search index: $project_name"
    if npx annosearch init --index "$project_name"; then
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
    
    # Construct manifest URL on the web service
    local manifest_url="http://localhost:8080/iiif/${project_name}.json"
    
    log_info "Loading from manifest URL: $manifest_url"
    
    # Check if manifest exists
    if ! curl -s -f --max-time 10 "$manifest_url" > /dev/null 2>&1; then
        log_error "Manifest not found at: $manifest_url"
        log_error "Please ensure the manifest has been generated and web service is running"
        return 1
    fi
    
    # Load the manifest into annosearch
    log_info "Loading IIIF Manifest into search index..."
    if npx annosearch load --index "$project_name" --type Manifest --uri "$manifest_url"; then
        log_success "IIIF Manifest loaded successfully into search index"
        
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
    log_info "This script requires the full IIIF stack to be running."
    log_info "Make sure you have run ./bootstrap.sh first."
    log_info ""
    
    # Check if annosearch directory exists
    if [ ! -d "$ANNOSEARCH_DIR" ]; then
        log_error "AnnoSearch directory not found: $ANNOSEARCH_DIR"
        log_error "Please ensure annosearch repository is cloned"
        exit 1
    fi
    
    # Wait for services to be ready
    if ! wait_for_annosearch; then
        log_error "AnnoSearch service is not available"
        exit 1
    fi
    
    if ! wait_for_web_service; then
        log_error "Web service is not available"
        exit 1
    fi
    
    # Create/recreate search index
    if ! create_index "$PROJECT_NAME"; then
        log_error "Failed to set up search index"
        exit 1
    fi
    
    # Load annotations into search index
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
  - annosearch service running on localhost:3000
  - web service running on localhost:8080 with generated IIIF manifests
  - jq command-line JSON processor

The script will:
1. Create a search index for the project
2. Load annotations from IIIF manifest served by web server
3. Make them searchable via IIIF Content Search API

EOF
    exit 0
fi

# Run main function
main