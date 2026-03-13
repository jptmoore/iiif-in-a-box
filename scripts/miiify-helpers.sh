#!/bin/bash
# Miiify v2 Workflow Helper Functions
# This script contains functions for managing the Miiify annotation workflow

# Extract the canvas URL from the target field of the first annotation JSON found in a folder.
# Handles all W3C Web Annotation target forms:
#   1. Plain string:  "target": "http://example.org/canvas/page01"
#   2. Object:        "target": { "source": "http://...", "selector": {...} }
#   3. Array:         "target": ["http://..."] or [{ "source": "http://..." }]
# Returns the first URL found, or empty string if none.
extract_annotation_target() {
    local anno_folder="$1"
    local json_file
    json_file=$(find "$anno_folder" -name "*.json" -type f 2>/dev/null | sort | head -1)
    [ -z "$json_file" ] && return 0

    local result

    # Try "source" field first (covers object and array-of-objects forms)
    result=$(grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_file" 2>/dev/null | \
        head -1 | sed 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    [ -n "$result" ] && { echo "$result"; return 0; }

    # Fall back to plain string target: "target": "http://..."
    # Match the target field value when it is a plain string (not an object/array)
    result=$(grep -o '"target"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_file" 2>/dev/null | \
        head -1 | sed 's/.*"target"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    [ -n "$result" ] && { echo "$result"; return 0; }

    return 0
}

# Function to import annotations into git store
miiify_import_annotations() {
    local input_dir="$1"
    local output_dir="$2"
    
    log_info "Importing annotations into Miiify git store..."
    
    # Check if annotations directory exists
    if [ ! -d "${input_dir}/annotations" ]; then
        log_warning "No annotations directory found in ${input_dir}"
        return 0
    fi
    
    # Check if there are any annotation files
    local annotation_count=$(find "${input_dir}/annotations" -name "*.json" -type f | wc -l)
    if [ "$annotation_count" -eq 0 ]; then
        log_warning "No annotation files found in ${input_dir}/annotations"
        return 0
    fi
    
    log_info "Found ${annotation_count} annotation files"
    
    # Create output directories
    mkdir -p "${output_dir}/miiify/git_store"
    mkdir -p "${output_dir}/miiify/pack_store"
    
    # Import annotations using Miiify v2
    log_info "Running miiify-import..."
    docker run --rm \
        --platform linux/amd64 \
        -v "${input_dir}/annotations":/home/miiify/annotations:ro \
        -v "${output_dir}/miiify/git_store":/home/miiify/git_store \
        ghcr.io/nationalarchives/miiify:latest \
        /home/miiify/miiify-import --input ./annotations --git ./git_store
    
    if [ $? -ne 0 ]; then
        log_error "Failed to import annotations"
        return 1
    fi
    
    log_success "Annotations imported to git store"
    return 0
}

# Function to compile git store to pack store
miiify_compile_pack() {
    local output_dir="$1"
    
    log_info "Compiling git store to pack store..."
    
    # Check if git_store exists
    if [ ! -d "${output_dir}/miiify/git_store" ]; then
        log_error "Git store not found at ${output_dir}/miiify/git_store"
        return 1
    fi
    
    # Compile git store to pack store
    log_info "Running miiify-compile..."
    docker run --rm \
        --platform linux/amd64 \
        -v "${output_dir}/miiify/git_store":/home/miiify/git_store:ro \
        -v "${output_dir}/miiify/pack_store":/home/miiify/pack_store \
        ghcr.io/nationalarchives/miiify:latest \
        /home/miiify/miiify-compile --git ./git_store --pack ./pack_store
    
    if [ $? -ne 0 ]; then
        log_error "Failed to compile pack store"
        return 1
    fi
    
    log_success "Pack store compiled successfully"
    return 0
}

# Legacy functions removed - services are now managed via main docker-compose.yml
# Use start_all_services() and stop_services() in bootstrap.sh instead

# Function to get annotation count from pack store
miiify_get_annotation_count() {
    local output_dir="$1"
    
    # This is a simple check - could be enhanced
    if [ -d "${output_dir}/miiify/pack_store" ]; then
        # Count container directories (rough estimate)
        local count=$(find "${output_dir}/miiify/pack_store" -type d -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
        echo "$count containers"
    else
        echo "0 containers"
    fi
}

# Function to run full Miiify workflow (import → compile)
miiify_full_workflow() {
    local input_dir="$1"
    local output_dir="$2"
    local base_url="$3"
    
    log_info "Running full Miiify workflow..."
    
    # Step 1: Import
    if ! miiify_import_annotations "$input_dir" "$output_dir"; then
        log_error "Miiify import failed"
        return 1
    fi
    
    # Step 2: Compile
    if ! miiify_compile_pack "$output_dir"; then
        log_error "Miiify compile failed"
        return 1
    fi
    
    # Note: Service will be started later by start_all_services()
    
    log_success "Miiify workflow completed successfully"
    log_info "Pack store ready at: ${output_dir}/miiify/pack_store"
    return 0
}
