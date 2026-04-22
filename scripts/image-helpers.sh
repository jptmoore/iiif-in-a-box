#!/bin/bash
# Image Processing Helper Functions
# This script contains functions for processing and managing images

# Images are copied as-is preserving the directory structure from the input.
# The directory structure determines the IIIF hierarchy:
# - Flat directory = Single Manifest
# - Subdirectories = Collection with Manifests per subdirectory
# Canvas IDs match the relative file path (without extension)

# Function to process images
process_images() {
    local input_dir="$1"
    local output_dir="$2"
    local project_name="$3"
    
    log_info "Processing images..."
    
    # Check if images directory exists
    if [ ! -d "${input_dir}/images" ]; then
        log_warning "No images directory found in ${input_dir}"
        return 0
    fi
    
    # Count images (recursively to include subdirectories)
    local image_count=$(find "${input_dir}/images" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | wc -l)
    
    if [ "$image_count" -eq 0 ]; then
        log_warning "No image files found in ${input_dir}/images"
        return 0
    fi
    
    log_info "Found ${image_count} image files"
    
    # Copy entire images directory structure as-is
    log_info "Copying images (preserving directory structure)..."
    mkdir -p "${output_dir}/web/images"
    
    # Use rsync or cp -r to preserve structure
    if command -v rsync &> /dev/null; then
        rsync -a "${input_dir}/images/" "${output_dir}/web/images/"
    else
        cp -r "${input_dir}/images/"* "${output_dir}/web/images/" 2>/dev/null || true
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Failed to copy images"
        return 1
    fi
    
    log_success "Images processed: ${image_count} files"
    return 0
}
