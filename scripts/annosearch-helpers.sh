#!/bin/bash
# AnnoSearch Helper Functions
# Functions for indexing annotations using AnnoSearch Docker container

# Function to create/recreate search index
create_annosearch_index() {
    local project_name="$1"
    
    log_info "Setting up search index for project: $project_name"
    
    # Try to delete existing index (silently ignore errors - 404 is expected if index doesn't exist)
    log_info "Cleaning up any existing index: $project_name"
    docker exec iiif-annosearch node /app/dist/index.js delete --index "$project_name" >/dev/null 2>&1 || true
    
    # Create new index
    log_info "Creating new search index: $project_name"
    if docker exec iiif-annosearch node /app/dist/index.js init --index "$project_name"; then
        log_success "Search index '$project_name' created successfully"
        return 0
    else
        log_error "Failed to create search index"
        return 1
    fi
}

# Function to load annotations from manifest URL into search index
load_annosearch_data() {
    local project_name="$1"
    local hostname="$2"
    
    log_info "Loading annotations from IIIF manifest..."
    
    # Construct manifest URL - use internal Docker network name
    local manifest_url="http://iiif-nginx/iiif/${project_name}.json"
    
    log_info "Loading from manifest URL: $manifest_url"
    
    # Check if manifest file exists in the output directory
    local manifest_file="${OUTPUT_DIR}/web/iiif/${project_name}.json"
    if [ ! -f "$manifest_file" ]; then
        log_error "Manifest file not found at: $manifest_file"
        log_error "Please ensure the manifest has been generated"
        return 1
    fi
    
    # Detect whether this is a Manifest or Collection
    local manifest_json=$(cat "$manifest_file")
    local manifest_type=$(echo "$manifest_json" | grep -o '"type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
    
    if [ -z "$manifest_type" ]; then
        log_error "Could not detect manifest type (Manifest or Collection)"
        return 1
    fi
    
    log_info "Detected IIIF type: $manifest_type"
    
    # Load the manifest into annosearch using Docker exec
    log_info "Loading IIIF $manifest_type into search index..."
    if docker exec iiif-annosearch node /app/dist/index.js load --index "$project_name" --type "$manifest_type" --uri "$manifest_url"; then
        log_success "IIIF $manifest_type loaded successfully into search index"
        
        # Get some stats about what was loaded
        log_info "Manifest URL (internal): $manifest_url"
        log_success "Search API available at: ${hostname}/annosearch/${project_name}/search"
        
        return 0
    else
        log_error "Failed to load IIIF Manifest from: $manifest_url"
        return 1
    fi
}

# Generic readiness probe: GET an HTTP URL from inside the iiif-nginx container.
# Avoids the need for each upstream image to ship its own probe tool
# (miiify is FROM scratch, quickwit is debian-slim without wget, etc.).
# $1: human-readable service name
# $2: URL to probe (e.g. http://miiify:10000/)
# $3: max_attempts (optional, default 15)
wait_for_http() {
    local name="$1"
    local url="$2"
    local max_attempts="${3:-15}"
    local attempt=0

    log_info "Verifying ${name} HTTP endpoint..."

    while [ $attempt -lt $max_attempts ]; do
        if docker exec iiif-nginx wget -q -O - "$url" >/dev/null 2>&1; then
            log_success "${name} is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    log_error "${name} HTTP endpoint did not respond within ${max_attempts}s ($url)"
    return 1
}

# Function to wait for annosearch service to be ready.
wait_for_annosearch() {
    wait_for_http "AnnoSearch" "http://annosearch:3000/"
}

# Function to wait for miiify service to be ready.
# Miiify ships FROM scratch with no probe tools, so it has no in-container
# healthcheck. We probe it externally from the nginx container.
wait_for_miiify() {
    wait_for_http "Miiify" "http://miiify:10000/"
}

# Function to wait for tamerlane viewer to be ready.
wait_for_tamerlane() {
    wait_for_http "Tamerlane" "http://tamerlane:3001/"
}

# Function to wait for quickwit search backend to be ready.
wait_for_quickwit() {
    wait_for_http "Quickwit" "http://quickwit:7280/health/livez"
}
