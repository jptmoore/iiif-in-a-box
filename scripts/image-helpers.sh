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

# Validate that every image under <input>/images has a matching annotation
# folder under <input>/annotations, and that no annotation folders are
# orphaned. Annotation folder names mirror the image's relative path with
# `/` converted to `-` (the format Miiify expects).
validate_annotation_naming() {
    local input_dir="$1"
    local images_dir="${input_dir}/images"
    local annotations_dir="${input_dir}/annotations"

    if [ ! -d "$annotations_dir" ]; then
        log_error "No annotations directory found: ${input_dir}/annotations"
        log_error "IIIF-in-a-Box requires annotations for all images"
        log_error "Create annotation directories matching your image paths (with / converted to -):"
        log_error "  images/photo.jpg → annotations/photo/"
        log_error "  images/chapter1/page01.jpg → annotations/chapter1-page01/"
        return 1
    fi

    log_info "Validating annotation folder structure..."

    local validation_errors=0

    while IFS= read -r -d '' image_file; do
        local rel_path="${image_file#$images_dir/}"
        local rel_path_no_ext="${rel_path%.*}"
        local expected_annotation_folder=$(echo "$rel_path_no_ext" | tr '/' '-')

        if [ ! -d "${annotations_dir}/${expected_annotation_folder}" ]; then
            log_error "Missing annotation folder for image: $rel_path"
            log_error "  Expected: ${annotations_dir}/${expected_annotation_folder}/"
            ((validation_errors++))
        fi
    done < <(find "$images_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) -print0)

    if [ $validation_errors -gt 0 ]; then
        log_error "Found $validation_errors annotation folder error(s)"
        log_error "Annotation folders must match image paths with / converted to -"
        log_error "Examples:"
        log_error "  images/photo.jpg               → annotations/photo/"
        log_error "  images/chapter1/page01.jpg     → annotations/chapter1-page01/"
        log_error "  images/vol1/ch1/p01.jpg        → annotations/vol1-ch1-p01/"
        return 1
    fi

    # Check for orphaned annotation folders (annotations without matching image).
    local orphaned_count=0
    local expected_folders=()

    while IFS= read -r -d '' image_file; do
        local rel_path="${image_file#$images_dir/}"
        local rel_path_no_ext="${rel_path%.*}"
        local folder_name=$(echo "$rel_path_no_ext" | tr '/' '-')
        expected_folders+=("$folder_name")
    done < <(find "$images_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) -print0)

    while IFS= read -r -d '' anno_folder; do
        local folder_name=$(basename "$anno_folder")

        local found=0
        for expected in "${expected_folders[@]}"; do
            if [ "$folder_name" = "$expected" ]; then
                found=1
                break
            fi
        done

        if [ $found -eq 0 ]; then
            log_warning "Orphaned annotation folder (no corresponding image): ${folder_name}"
            ((orphaned_count++))
        fi
    done < <(find "$annotations_dir" -mindepth 1 -maxdepth 1 -type d -print0)

    if [ $orphaned_count -gt 0 ]; then
        log_error "Found $orphaned_count orphaned annotation folder(s) without corresponding images"
        log_error "These folders will cause old/incorrect data to be imported"
        log_error "Please remove annotation folders that don't match your current images"
        return 1
    fi

    log_success "Annotation structure validation passed"
    return 0
}
