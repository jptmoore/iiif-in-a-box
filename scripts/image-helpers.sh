#!/bin/bash
# Image Processing Helper Functions
# This script contains functions for processing and managing images

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
    
    # Count images
    local image_count=$(find "${input_dir}/images" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | wc -l)
    
    if [ "$image_count" -eq 0 ]; then
        log_warning "No image files found in ${input_dir}/images"
        return 0
    fi
    
    log_info "Found ${image_count} image files"
    
    # Create output directory for images
    mkdir -p "${output_dir}/web/images"
    
    # Copy or symlink images
    # Using rsync for efficient copying (only copies if changed)
    log_info "Copying images to output directory..."
    rsync -av --delete "${input_dir}/images/" "${output_dir}/web/images/"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to copy images"
        return 1
    fi
    
    log_success "Images processed: ${image_count} files"
    return 0
}

# Function to get image list
get_image_list() {
    local input_dir="$1"
    
    if [ ! -d "${input_dir}/images" ]; then
        echo ""
        return
    fi
    
    find "${input_dir}/images" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) -printf "%f\n" | sort
}

# Function to validate image files
validate_images() {
    local input_dir="$1"
    
    log_info "Validating image files..."
    
    if [ ! -d "${input_dir}/images" ]; then
        log_warning "No images directory found"
        return 0
    fi
    
    local valid_count=0
    local invalid_count=0
    
    while IFS= read -r -d '' image_file; do
        # Basic validation - check if file is readable and has size > 0
        if [ -r "$image_file" ] && [ -s "$image_file" ]; then
            ((valid_count++))
        else
            log_warning "Invalid or empty image: $image_file"
            ((invalid_count++))
        fi
    done < <(find "${input_dir}/images" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) -print0)
    
    log_info "Image validation: ${valid_count} valid, ${invalid_count} invalid"
    
    if [ "$invalid_count" -gt 0 ]; then
        return 1
    fi
    
    return 0
}
