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
    
    # Check if manifest exists via nginx (use the public hostname)
    if ! curl -s -f --max-time 10 "${hostname}/iiif/${project_name}.json" > /dev/null 2>&1; then
        log_error "Manifest not found at: ${hostname}/iiif/${project_name}.json"
        log_error "Please ensure the manifest has been generated and nginx service is running"
        return 1
    fi
    
    # Load the manifest into annosearch using Docker exec
    log_info "Loading IIIF Collection into search index..."
    if docker exec iiif-annosearch node /app/dist/index.js load --index "$project_name" --type Collection --uri "$manifest_url"; then
        log_success "IIIF Collection loaded successfully into search index"
        
        # Get some stats about what was loaded
        log_info "Manifest URL: $manifest_url"
        log_success "Search API available at: ${hostname}/annosearch/${project_name}/search"
        
        return 0
    else
        log_error "Failed to load IIIF Manifest from: $manifest_url"
        return 1
    fi
}

# Function to wait for annosearch service to be ready
wait_for_annosearch() {
    log_info "Waiting for AnnoSearch service to be ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if docker exec iiif-annosearch test -f /app/package.json 2>/dev/null; then
            log_success "AnnoSearch service is ready"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 1
    done
    
    log_error "AnnoSearch service failed to become ready"
    return 1
}
