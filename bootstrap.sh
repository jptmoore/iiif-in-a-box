#!/bin/bash
# IIIF-In-A-Box Bootstrap Script v2
# Uses Miiify v2 with separate input/output directories
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${BLUE}[INFO]${NC} $1" || true; }
log_step() { echo -e "  ${BLUE}→${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default configuration
DEFAULT_OUTPUT_DIR="./output"
DEFAULT_HOSTNAME="http://localhost:8080"
VERBOSE=false
DOCKER_COMPOSE_CMD="docker compose"

# Version
SCRIPT_DIR_EARLY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IIIF_VERSION=$(cat "${SCRIPT_DIR_EARLY}/VERSION" 2>/dev/null || echo "unknown")

# Source helper scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/config-helpers.sh"
source "${SCRIPT_DIR}/scripts/miiify-helpers.sh"
source "${SCRIPT_DIR}/scripts/image-helpers.sh"
source "${SCRIPT_DIR}/scripts/annosearch-helpers.sh"

# Function to show help
show_help() {
    cat << EOF
IIIF-In-A-Box Bootstrap Script v2 (Miiify v2)

Usage: $0 [OPTIONS] [COMMAND]

Options:
  --input-dir, -i DIR         Input directory containing source data (required for build)
                               Example: /home/john/git/domesday-in-a-box
  --output-dir, -o DIR        Output directory for generated files
                               (default: ./output)
  --hostname, --host URL      Base URL for the IIIF service 
                               Port defaults to 80 if not specified
                               Examples: http://example.com (port 80)
                                        http://localhost:8080 (port 8080)
                               (default: http://localhost:8080)
  --pull                       Force pull latest Docker images before starting
  --verbose, -v                Show detailed build output (default: minimal progress)
  --help, -h                   Show this help message

Commands:
  build                        - Build IIIF service from input directory
  status                       - Show service status
  stop                         - Stop all services
  restart                      - Restart all services
  logs                         - Show service logs
  clean                        - Stop services and clean output directory
  maintenance                  - Enable maintenance mode (stops services, shows maintenance page)

Examples:
  # Build from input directory (first time)
  $0 build --input-dir /home/john/git/domesday-in-a-box
  
  # Build with custom output directory
  $0 build -i /home/john/git/domesday-in-a-box -o /home/john/iiif-output
  
  # Build for deployment with external hostname
  $0 build -i ~/domesday-in-a-box --hostname http://192.168.1.100
  
  # Build with custom port
  $0 build -i ~/domesday-in-a-box --hostname http://example.com:8080
  
  # Check service status
  $0 status
  
  # View logs
  $0 logs
  
  # Stop all services
  $0 stop
  
  # Clean everything (stop services, remove output)
  $0 clean

EOF
}

# Function to parse command line arguments
parse_arguments() {
    INPUT_DIR=""
    OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
    HOSTNAME="$DEFAULT_HOSTNAME"
    FORCE_PULL=false
    VERBOSE=false
    COMMAND=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --input-dir|-i)
                INPUT_DIR="$2"
                shift 2
                ;;
            --output-dir|-o)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --hostname|--host)
                HOSTNAME="$2"
                shift 2
                ;;
            --pull)
                FORCE_PULL=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            build|status|stop|restart|logs|clean|maintenance)
                COMMAND="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set default command if none provided
    if [ -z "$COMMAND" ]; then
        COMMAND="build"
    fi
    
    # Validate input directory for build command
    if [ "$COMMAND" = "build" ] && [ -z "$INPUT_DIR" ]; then
        log_error "Input directory is required for build command"
        log_info "Use: $0 build --input-dir /path/to/input"
        exit 1
    fi
}

# Function to check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        log_error "docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check for docker compose
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        log_error "Neither 'docker compose' nor 'docker-compose' is available"
        exit 1
    fi
    
    # Check for rsync (for image copying)
    if ! command -v rsync &> /dev/null; then
        log_warning "rsync not found, will use cp for copying files"
    fi
    
    log_success "All dependencies are available"
}

# Validate annotation folder naming matches image structure
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
    
    # Check all images (recursively) and validate their corresponding annotation folders
    while IFS= read -r -d '' image_file; do
        local image_basename=$(basename "$image_file")
        local image_name="${image_basename%.*}"
        
        # Get relative path from images directory (without extension)
        local rel_path="${image_file#$images_dir/}"
        local rel_path_no_ext="${rel_path%.*}"
        
        # Convert slashes to dashes for annotation folder name (Miiify container format)
        local expected_annotation_folder=$(echo "$rel_path_no_ext" | tr '/' '-')
        
        # Check if annotation folder exists
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
    
    # Check for orphaned annotation folders (annotations without corresponding images)
    local orphaned_count=0
    local expected_folders=()
    
    # Build list of expected annotation folder names from images
    while IFS= read -r -d '' image_file; do
        local rel_path="${image_file#$images_dir/}"
        local rel_path_no_ext="${rel_path%.*}"
        local folder_name=$(echo "$rel_path_no_ext" | tr '/' '-')
        expected_folders+=("$folder_name")
    done < <(find "$images_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) -print0)
    
    # Check all annotation folders
    while IFS= read -r -d '' anno_folder; do
        local folder_name=$(basename "$anno_folder")
        
        # Check if this folder corresponds to an image
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

# Detect if flat files use dash-separated hierarchical naming
# Returns the hierarchy depth (number of common dash-separated segments before the unique part)
detect_dash_hierarchy() {
    local images_dir="$1"

    # Get the first image file
    local first_file
    first_file=$(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort | head -1)

    if [ -z "$first_file" ]; then
        echo "0"
        return
    fi

    local first_basename
    first_basename=$(basename "$first_file")
    local name="${first_basename%.*}"

    # Return the number of dashes = number of hierarchy levels above the canvas
    local dash_count
    dash_count=$(echo "$name" | tr -cd '-' | wc -c)
    echo "$dash_count"
}

# Generate collection structure from dash-separated flat files
# Supports arbitrary nesting: domesday-volume1-chapter1-page01.tif
# Creates: domesday.json (Collection) → volume1.json (Collection) → chapter1.json (Manifest)
generate_collection_from_dashed_files() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    local input_dir="$5"
    local hierarchy_depth="$6"
    
    local images_dir="${OUTPUT_DIR}/web/images"
    
    # Get all image files
    local all_files=($(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort))
    
    if [ ${#all_files[@]} -eq 0 ]; then
        log_error "No image files found"
        return 1
    fi
    
    # Extract collection name from first file (first segment)
    local first_file=$(basename "${all_files[0]}")
    local first_basename="${first_file%.*}"
    local collection_name=$(echo "$first_basename" | cut -d'-' -f1)
    
    log_info "Generating Collection structure for: $collection_name (depth: $hierarchy_depth)"
    
    # Get metadata and provider from config if available
    local metadata_json=$(get_config_metadata "${input_dir}/config.yml")
    local provider_json=$(get_config_provider "${input_dir}/config.yml")
    
    # Build the collection recursively
    build_dashed_collection_recursive "$images_dir" "$collection_name" "$hostname" 1 "$hierarchy_depth" "$metadata_json" "$provider_json"
    
    # Set MANIFEST_NAME and VIEWER_MANIFEST for later use (top-level collection)
    export MANIFEST_NAME="$collection_name"
    export VIEWER_MANIFEST="${collection_name}.json"
    export MANIFEST_TYPE="Collection"
}

# Recursive function to build collections/manifests from dash-separated files
# $1: images_dir
# $2: prefix at this level (e.g., "domesday", "domesday-volume1")
# $3: hostname
# $4: current_depth (1-based)
# $5: max_depth
# $6: metadata_json (optional, for top-level only)
# $7: provider_json (optional, for top-level only)
build_dashed_collection_recursive() {
    local images_dir="$1"
    local prefix="$2"
    local hostname="$3"
    local current_depth="$4"
    local max_depth="$5"
    local metadata_json="$6"
    local provider_json="$7"
    
    # Get the simple name (last segment of prefix)
    local simple_name="${prefix##*-}"
    [ -z "$simple_name" ] && simple_name="$prefix"
    
    # If we're at the second-to-last level, create Manifest
    if [ "$current_depth" -eq "$max_depth" ]; then
        build_dashed_manifest "$images_dir" "$prefix" "$simple_name" "$hostname" "$metadata_json" "$provider_json"
        return
    fi
    
    # Otherwise, create Collection and recurse
    # Find all unique child prefixes (without using associative arrays for compatibility)
    local children_list=""
    while IFS= read -r -d '' image_file; do
        local basename=$(basename "$image_file")
        local name="${basename%.*}"
        
        # Check if this file matches our prefix
        if [[ "$name" == "$prefix-"* ]]; then
            # Extract the next segment
            local remainder="${name#$prefix-}"
            local next_segment=$(echo "$remainder" | cut -d'-' -f1)
            children_list="${children_list}${next_segment}"$'\n'
        fi
    done < <(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) -print0)
    
    # Get unique sorted children
    local unique_children=$(echo "$children_list" | sort -u)
    
    # Build items for this collection
    local items_json=""
    local item_count=0
    for child in $unique_children; do
        [ -z "$child" ] && continue
        local child_prefix="$prefix-$child"
        local next_depth=$((current_depth + 1))
        
        # Recursively build child (pass metadata/provider through all levels)
        build_dashed_collection_recursive "$images_dir" "$child_prefix" "$hostname" "$next_depth" "$max_depth" "$metadata_json" "$provider_json"
        
        # Determine type
        local child_type="Manifest"
        if [ "$next_depth" -lt "$max_depth" ]; then
            child_type="Collection"
        fi
        
        # Capitalize first letter of child name for label (bash 3.2 compatible)
        local child_label=$(echo "$child" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
        
        ((item_count++))
        [ $item_count -gt 1 ] && items_json+=","
        items_json+=$(cat << ITEM_EOF

    {
      "id": "${hostname}/iiif/${child}.json",
      "type": "${child_type}",
      "label": { "en": ["${child_label}"] }
    }
ITEM_EOF
)
    done
    
    # Create the collection JSON
    local collection_path="${OUTPUT_DIR}/web/iiif/${simple_name}.json"
    local service_block=""
    local metadata_block=""
    local provider_block=""
    
    # Add search service only to top-level (depth 1)
    if [ "$current_depth" -eq 1 ]; then
        service_block=",
  \"service\": [
    {
      \"id\": \"${hostname}/annosearch/${simple_name}/search\",
      \"type\": \"SearchService2\",
      \"service\": [
        {
          \"id\": \"${hostname}/annosearch/${simple_name}/autocomplete\",
          \"type\": \"AutoCompleteService2\"
        }
      ]
    }
  ]"
    fi

    # Always add metadata and provider at every level
    if [ -n "$metadata_json" ] && [ "$metadata_json" != "null" ]; then
        metadata_block=",
  \"metadata\": $metadata_json"
    fi
    
    if [ -n "$provider_json" ] && [ "$provider_json" != "null" ]; then
        provider_block=",
  \"provider\": $provider_json"
    fi
    
    cat > "$collection_path" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${simple_name}.json",
  "type": "Collection",
  "label": {
    "en": ["$(echo $simple_name | sed 's/.*/\u&/')"]
  },
  "items": [${items_json}
  ]${service_block}${metadata_block}${provider_block}
}
EOF
    
    log_success "Generated Collection: ${simple_name}.json with ${item_count} item(s)"
}

# Build a manifest from dash-separated files with given prefix
# $1: images_dir
# $2: prefix (e.g., "domesday-lincolnshire")
# $3: simple_name (e.g., "lincolnshire")
# $4: hostname
# $5: metadata_json (optional)
# $6: provider_json (optional)
build_dashed_manifest() {
    local images_dir="$1"
    local prefix="$2"
    local simple_name="$3"
    local hostname="$4"
    local metadata_json="$5"
    local provider_json="$6"
    
    local manifest_path="${OUTPUT_DIR}/web/iiif/${simple_name}.json"
    local canvases_json=""
    local canvas_count=0
    
    # Find all images matching this prefix and sort them
    for image_file in $(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort); do
        local image_basename=$(basename "$image_file")
        local image_name="${image_basename%.*}"
        
        # Check if this file matches our prefix
        if [[ "$image_name" == "$prefix-"* ]]; then
            ((canvas_count++))

            # Derive canvas ID from annotation target if available.
            # This ensures the manifest canvas ID always matches what annotations reference,
            # regardless of what hostname was used when annotations were authored.
            local anno_folder="${INPUT_DIR}/annotations/${image_name}"
            local canvas_key="${image_name##*-}"
            local canvas_id
            local raw_target_source
            raw_target_source=$(extract_annotation_target "$anno_folder" "$canvas_key")

            if [ -n "$raw_target_source" ]; then
                # Use target.source as-is — canvas IDs are opaque identifiers and don't need to resolve.
                canvas_id="$raw_target_source"
                log_info "Canvas ID from annotation target: $canvas_id"
            else
                # No annotations — fall back to generated canvas ID
                local generated_id=$(echo "$image_name" | tr '-' '/')
                canvas_id="${hostname}/${generated_id%/*}/canvas/${generated_id##*/}"
                log_info "Canvas ID generated (no annotations): $canvas_id"
            fi
            
            # Get image dimensions
            local width=3000
            local height=2000
            if command -v identify &> /dev/null; then
                local dims=$(identify -format "%w %h\n" "$image_file" 2>/dev/null | head -1 2>/dev/null || echo "3000 2000")
                width=$(echo "$dims" | awk '{print $1}')
                height=$(echo "$dims" | awk '{print $2}')
            fi
            
            # Add to canvases
            [ $canvas_count -gt 1 ] && canvases_json+=","
            canvases_json+=$(cat << CANVAS_EOF

    {
      "id": "${canvas_id}",
      "type": "Canvas",
      "label": { "en": ["${canvas_id##*/}"] },
      "height": ${height},
      "width": ${width},
      "items": [
        {
          "id": "${canvas_id}/page/1",
          "type": "AnnotationPage",
          "items": [
            {
              "id": "${canvas_id}/page/1/annotation/1",
              "type": "Annotation",
              "motivation": "painting",
              "body": {
                "id": "${hostname}/iiif/${image_basename}/full/max/0/default.jpg",
                "type": "Image",
                "format": "image/jpeg",
                "height": ${height},
                "width": ${width},
                "service": [
                  {
                    "id": "${hostname}/iiif/${image_basename}",
                    "type": "ImageService3",
                    "profile": "level1"
                  }
                ]
              },
              "target": "${canvas_id}"
            }
          ]
        }
      ],
      "annotations": [
        {
          "id": "${hostname}/miiify/${image_name}/?page=0",
          "type": "AnnotationPage"
        }
      ]
    }
CANVAS_EOF
)
        fi
    done
    
    # Build optional blocks
    local metadata_block=""
    local provider_block=""
    
    if [ -n "$metadata_json" ] && [ "$metadata_json" != "null" ]; then
        metadata_block=",
  \"metadata\": $metadata_json"
    fi
    
    if [ -n "$provider_json" ] && [ "$provider_json" != "null" ]; then
        provider_block=",
  \"provider\": $provider_json"
    fi
    
    # Create Manifest
    cat > "$manifest_path" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${simple_name}.json",
  "type": "Manifest",
  "label": {
    "en": ["$(echo $simple_name | sed 's/.*/\u&/')"]
  },
  "items": [${canvases_json}
  ]${metadata_block}${provider_block}
}
EOF
    
    log_success "Generated Manifest: ${simple_name}.json with ${canvas_count} canvas(es)"
}

# Function to generate IIIF manifest for a project
generate_manifest() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    local input_dir="$5"
    
    log_info "Generating IIIF manifest for project: $project_name"

    # Naming strategy (dash-separated flat files only):
    # - foo-canvas.jpg          → foo.json (Manifest)
    # - foo-bar-canvas.jpg      → foo.json (Collection) → bar.json (Manifest)
    # - foo-bar-baz-canvas.jpg  → foo.json (Collection) → bar.json (Collection) → baz.json (Manifest)
    # The number of dashes determines depth; the last segment is always the canvas.
    
    mkdir -p "${OUTPUT_DIR}/web/iiif"
    local images_dir="${OUTPUT_DIR}/web/images"
    
    # Check if images are organized in subdirectories or flat
    local has_subdirs=false
    if [ -d "$images_dir" ]; then
        # Check if there are any subdirectories with images
        if find "$images_dir" -mindepth 2 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | head -1 | grep -q .; then
            has_subdirs=true
        fi
    fi
    
    if [ "$has_subdirs" = true ]; then
        log_error "Subdirectory structure not supported - use dash-separated flat files"
        log_error "Example: mybook-page01.jpg, mybook-page02.jpg"
        return 1
    else
        # Check if flat files have dash-separated hierarchical naming
        local hierarchy_depth=$(detect_dash_hierarchy "$images_dir")
        if [ "$hierarchy_depth" -eq 0 ]; then
            log_error "No dash-separated naming detected"
            log_error "Images must use dash-separated names:"
            log_error "  Single manifest: mybook-page01.jpg"
            log_error "  Collection+Manifest: collection-mybook-page01.jpg"
            return 1
        elif [ "$hierarchy_depth" -eq 1 ]; then
            log_info "Detected single manifest (depth: 1) - generating Manifest"
            generate_single_manifest "$project_name" "$project_title" "$project_description" "$hostname" "$input_dir"
        else
            log_info "Detected dash-separated hierarchical naming (depth: $hierarchy_depth) - generating Collection structure"
            generate_collection_from_dashed_files "$project_name" "$project_title" "$project_description" "$hostname" "$input_dir" "$hierarchy_depth"
        fi
    fi
}

# Generate a single manifest from dash-separated files (manifest-canvas pattern)
generate_single_manifest() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    local input_dir="$5"
    
    local images_dir="${OUTPUT_DIR}/web/images"
    
    # Extract manifest name from first file (first segment before dash)
    local first_file=$(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | head -1)
    if [ -z "$first_file" ]; then
        log_error "No image files found"
        return 1
    fi
    
    local first_basename=$(basename "$first_file")
    local first_name="${first_basename%.*}"
    local manifest_name=$(echo "$first_name" | cut -d'-' -f1)
    
    log_info "Generating Manifest: ${manifest_name}.json"
    
    local manifest_path="${OUTPUT_DIR}/web/iiif/${manifest_name}.json"
    local canvases_json=""
    local canvas_count=0
    
    # Process each image as a Canvas
    if [ -d "$images_dir" ]; then
        for image_file in $(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort); do
            local image_basename=$(basename "$image_file")
            local image_name="${image_basename%.*}"
            
            ((canvas_count++))

            # Derive canvas ID from annotation target if available.
            local anno_folder="${INPUT_DIR}/annotations/${image_name}"
            local canvas_key="${image_name##*-}"
            local canvas_id
            local raw_target_source
            raw_target_source=$(extract_annotation_target "$anno_folder" "$canvas_key")

            if [ -n "$raw_target_source" ]; then
                canvas_id="$raw_target_source"
                log_info "Canvas ID from annotation target: $canvas_id"
            else
                canvas_id="${hostname}/canvas/${image_name}"
                log_info "Canvas ID generated (no annotations): $canvas_id"
            fi
            
            # Get image dimensions
            local width=3000
            local height=2000
            if command -v identify &> /dev/null; then
                local dims=$(identify -format "%w %h\n" "$image_file" 2>/dev/null | head -1 2>/dev/null || echo "3000 2000")
                width=$(echo "$dims" | awk '{print $1}')
                height=$(echo "$dims" | awk '{print $2}')
            fi
            
            # Add to canvases
            [ $canvas_count -gt 1 ] && canvases_json+=","
            canvases_json+=$(cat << CANVAS_EOF

    {
      "id": "${canvas_id}",
      "type": "Canvas",
      "label": { "en": ["${canvas_id##*/}"] },
      "height": ${height},
      "width": ${width},
      "items": [
        {
          "id": "${canvas_id}/page/1",
          "type": "AnnotationPage",
          "items": [
            {
              "id": "${canvas_id}/page/1/annotation/1",
              "type": "Annotation",
              "motivation": "painting",
              "body": {
                "id": "${hostname}/iiif/${image_basename}/full/max/0/default.jpg",
                "type": "Image",
                "format": "image/jpeg",
                "height": ${height},
                "width": ${width},
                "service": [
                  {
                    "id": "${hostname}/iiif/${image_basename}",
                    "type": "ImageService3",
                    "profile": "level1"
                  }
                ]
              },
              "target": "${canvas_id}"
            }
          ]
        }
      ],
      "annotations": [
        {
          "id": "${hostname}/miiify/${image_name}/?page=0",
          "type": "AnnotationPage"
        }
      ]
    }
CANVAS_EOF
)
        done
    fi
    
    # Get metadata and provider from config if available
    local metadata_json=$(get_config_metadata "${input_dir}/config.yml")
    local provider_json=$(get_config_provider "${input_dir}/config.yml")
    
    # Build optional blocks
    local metadata_block=""
    local provider_block=""
    
    if [ -n "$metadata_json" ] && [ "$metadata_json" != "null" ]; then
        metadata_block=",
  \"metadata\": $metadata_json"
    fi
    
    if [ -n "$provider_json" ] && [ "$provider_json" != "null" ]; then
        provider_block=",
  \"provider\": $provider_json"
    fi
    
    # Capitalize manifest name for label
    local manifest_label=$(echo "$manifest_name" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
    
    # Create single Manifest with all Canvases
    cat > "$manifest_path" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${manifest_name}.json",
  "type": "Manifest",
  "label": {
    "en": ["${manifest_label}"]
  },
  "summary": {
    "en": ["${project_description}"]
  },
  "items": [${canvases_json}
  ],
  "service": [
    {
      "id": "${hostname}/annosearch/${manifest_name}/search",
      "type": "SearchService2",
      "service": [
        {
          "id": "${hostname}/annosearch/${manifest_name}/autocomplete",
          "type": "AutoCompleteService2"
        }
      ]
    }
  ]${metadata_block}${provider_block}
}
EOF
    
    log_success "Generated Manifest: ${manifest_name}.json with ${canvas_count} canvas(es)"
    
    # Set MANIFEST_NAME, VIEWER_MANIFEST and MANIFEST_TYPE for later use
    export MANIFEST_NAME="$manifest_name"
    export VIEWER_MANIFEST="$manifest_name"
    export MANIFEST_TYPE="Manifest"
}

# Function to generate HTML viewer page from template
generate_viewer_page() {
    local page_name="$1"
    local manifest_name="$2"
    local project_title="$3"
    local project_description="$4"
    local hostname="$5"
    local manifest_type="${6:-Collection}"  # Default to Collection for backwards compatibility
    
    log_info "Generating viewer page: ${page_name}.html (loading manifest: ${manifest_name}.json)"
    
    mkdir -p "${OUTPUT_DIR}/web/pages"
    local page_path="${OUTPUT_DIR}/web/pages/${page_name}.html"
    local template_path="templates/pages/_template.html"
    
    if [ ! -f "$template_path" ]; then
        log_error "Template not found: $template_path"
        return 1
    fi
    
    # Replace placeholders in template
    # Note: 'demo' in the manifest URL gets replaced with the manifest name
    sed -e "s/Demo/${project_title}/g" \
        -e "s/demo/${manifest_name}/g" \
        -e "s|https://digitaldomesday.org|${hostname}|g" \
        -e "s/IIIF Collection/IIIF ${manifest_type}/g" \
        "$template_path" > "$page_path"
    
    log_success "Generated viewer page: ${page_path}"
    log_info "View at: ${hostname}/pages/${page_name}.html"
}

# Function to setup web content
setup_web_content() {
    log_info "Setting up web content..."
    
    # Copy static template files to output
    cp templates/services.html "${OUTPUT_DIR}/web/"
    sed -i "s/__VERSION__/${IIIF_VERSION}/g" "${OUTPUT_DIR}/web/services.html"
    cp templates/maintenance.html "${OUTPUT_DIR}/web/"

    # Generate index.html that redirects to the project viewer page
    cat > "${OUTPUT_DIR}/web/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="refresh" content="0;url=/pages/${PROJECT_NAME}.html">
  <title>Redirecting...</title>
</head>
<body>
  <script>window.location.replace('/pages/${PROJECT_NAME}.html');</script>
  <p><a href="/pages/${PROJECT_NAME}.html">Click here</a> if you are not redirected.</p>
</body>
</html>
EOF
    
    # Copy assets directory
    if [ -d "assets" ]; then
        cp -r assets "${OUTPUT_DIR}/web/"
        log_info "Copied assets to web directory"
    fi
    
    log_success "Web content setup complete"
}

# Function to create docker network
create_docker_network() {
    if ! docker network ls | grep -q "iiif-network"; then
        log_info "Creating shared Docker network..."
        docker network create iiif-network
        log_success "Docker network created"
    else
        log_info "Docker network already exists"
    fi
}

# AnnoSearch functions are now in scripts/annosearch-helpers.sh

# Function to build project
build_project() {
    echo ""
    echo -e "${BLUE}IIIF-in-a-Box v${IIIF_VERSION}${NC}"
    echo -e "  Input:    $INPUT_DIR"
    echo -e "  Output:   $OUTPUT_DIR"
    echo -e "  Hostname: $HOSTNAME"
    echo ""
    
    # Step 0: Stop any running services to avoid lock file issues
    log_step "Stopping any running services..."
    stop_services
    
    # Also stop maintenance mode if it's running
    docker compose -f nginx/docker-compose.maintenance.yml down 2>/dev/null || true
    
    # Step 1: Validate input directory
    log_step "Validating input directory..."
    if ! validate_input_directory "$INPUT_DIR"; then
        log_error "Input directory validation failed"
        exit 1
    fi
    
    # Step 2: Read configuration
    log_step "Reading configuration..."
    if ! read_project_config "$INPUT_DIR"; then
        log_error "Failed to read project configuration"
        exit 1
    fi
    
    # Step 2a: Check if yq is installed (required for YAML parsing)
    if ! check_yq_dependency; then
        log_error "yq is required but not installed"
        exit 1
    fi
    
    log_info "Project: $PROJECT_NAME | Title: $PROJECT_TITLE"
    
    # Step 3: Validate annotation naming
    log_step "Validating annotations..."
    if ! validate_annotation_naming "$INPUT_DIR"; then
        log_error "Annotation naming validation failed"
        exit 1
    fi
    
    # Step 4: Clean and create output directory structure
    log_step "Preparing output directory..."
    # Remove all contents to prevent any old data contamination
    rm -rf "$OUTPUT_DIR"/* 2>/dev/null || true
    mkdir -p "$OUTPUT_DIR"/{miiify/{git_store,pack_store},web/{iiif,pages,images},annosearch/qwdata,logs}
    
    # Store current project name for reference
    echo "$PROJECT_NAME" > "$OUTPUT_DIR/.project"
    
    # Step 5: Process images
    log_step "Processing images..."
    if ! process_images "$INPUT_DIR" "$OUTPUT_DIR" "$PROJECT_NAME"; then
        log_error "Image processing failed"
        exit 1
    fi

    # Step 6: Run Miiify workflow (import → compile)
    log_step "Running Miiify workflow..."
    if ! miiify_full_workflow "$INPUT_DIR" "$OUTPUT_DIR" "$HOSTNAME"; then
        log_error "Miiify workflow failed"
        exit 1
    fi
    
    # Step 7: Generate IIIF manifests
    log_step "Generating IIIF manifests..."
    if ! generate_manifest "$PROJECT_NAME" "$PROJECT_TITLE" "$PROJECT_DESCRIPTION" "$HOSTNAME" "$INPUT_DIR"; then
        log_error "Manifest generation failed"
        exit 1
    fi
    
    # Step 8: Generate HTML viewer pages
    # Derive manifest/collection name from directory structure
    MANIFEST_NAME="$PROJECT_NAME"
    VIEWER_MANIFEST="$PROJECT_NAME"
    
    if [ -d "${OUTPUT_DIR}/web/images" ]; then
        # Check if there are subdirectories (which means we generated a collection)
        if find "${OUTPUT_DIR}/web/images" -mindepth 2 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | head -1 | grep -q .; then
            # Find first subdirectory name for the collection/manifest name
            first_subdir=$(find "${OUTPUT_DIR}/web/images" -mindepth 1 -maxdepth 1 -type d | sort | head -1)
            if [ -n "$first_subdir" ]; then
                MANIFEST_NAME=$(basename "$first_subdir")
                VIEWER_MANIFEST=$(basename "$first_subdir")
            fi
        fi
    fi
    
    # Step 8: Generate HTML viewer page
    log_step "Generating viewer page..."
    if ! generate_viewer_page "$PROJECT_NAME" "$VIEWER_MANIFEST" "$PROJECT_TITLE" "$PROJECT_DESCRIPTION" "$HOSTNAME" "${MANIFEST_TYPE:-Collection}"; then
        log_error "Page generation failed"
        exit 1
    fi
    
    # Step 9: Setup web content
    log_step "Setting up web content..."
    setup_web_content
    
    # Step 10: Create Docker network
    create_docker_network
    
    # Step 10.5: Prepare Tamerlane image
    log_step "Preparing Tamerlane image..."
    if ! prepare_tamerlane_image; then
        log_error "Failed to prepare Tamerlane image"
        exit 1
    fi
    
    # Step 11: Start all services
    log_step "Starting services..."
    if ! start_all_services; then
        log_error "Failed to start all services"
        exit 1
    fi
    
    # Step 12: Wait for AnnoSearch to be ready
    log_step "Waiting for AnnoSearch..."
    if ! wait_for_annosearch; then
        log_warning "AnnoSearch not ready, skipping search indexing"
    else
        # Step 13: Create search index and load data
        log_step "Indexing search data..."
        # Use the derived manifest name for indexing, not the project name
        if create_annosearch_index "$MANIFEST_NAME"; then
            load_annosearch_data "$MANIFEST_NAME" "$HOSTNAME" || log_warning "Failed to load data into AnnoSearch"
        fi
    fi
    
    # Store current project name and build version for future reference
    echo "$PROJECT_NAME" > "$OUTPUT_DIR/.project"
    echo "$IIIF_VERSION" > "$OUTPUT_DIR/.version"

    print_build_summary "$PROJECT_NAME" "$MANIFEST_NAME" "$PROJECT_TITLE" "$HOSTNAME"
}

# Function to prepare Tamerlane image (pull from ghcr or use local)
prepare_tamerlane_image() {
    local ghcr_image="ghcr.io/tamerlaneviewer/tamerlane:latest"
    local local_image="tamerlane_tamerlane:latest"
    
    log_info "Preparing Tamerlane viewer image..."
    
    # Check if ghcr.io image exists locally
    if docker image inspect "$ghcr_image" &> /dev/null; then
        log_info "Tamerlane image already exists locally"
        docker tag "$ghcr_image" "$local_image"
        log_success "Tagged ${ghcr_image} as ${local_image}"
        return 0
    fi
    
    # Try to pull from GitHub Container Registry
    log_info "Pulling Tamerlane from GitHub Container Registry..."
    if docker pull "$ghcr_image" 2>/dev/null; then
        log_success "Successfully pulled Tamerlane from ghcr.io"
        docker tag "$ghcr_image" "$local_image"
        log_info "Tagged ${ghcr_image} as ${local_image}"
        return 0
    else
        log_error "Failed to pull Tamerlane from ghcr.io"
        log_error "Image not available - please authenticate with: docker login ghcr.io"
        return 1
    fi
}

# Function to start all services
start_all_services() {
    log_info "Starting all IIIF services..."

    # Extract port from hostname (default to 80 if not specified)
    if [[ "$HOSTNAME" =~ :([0-9]+)$ ]]; then
        export NGINX_PORT="${BASH_REMATCH[1]}"
    else
        export NGINX_PORT="80"
    fi

    # Export environment variables for docker-compose
    export OUTPUT_DIR
    export PROJECT_NAME
    export MIIIFY_BASE_URL="${HOSTNAME}/miiify"
    export ANNOSEARCH_PUBLIC_URL="${HOSTNAME}/annosearch"

    log_info "Output directory: $OUTPUT_DIR"
    log_info "Nginx port: $NGINX_PORT"
    log_info "Miiify base URL: $MIIIFY_BASE_URL"
    log_info "AnnoSearch public URL: $ANNOSEARCH_PUBLIC_URL"
    
    # Start all services using main docker-compose.yml
    log_info "Starting IIIF-in-a-Box services..."
    log_info "Environment variables for docker-compose:"
    log_info "  NGINX_PORT=$NGINX_PORT"
    log_info "  MIIIFY_BASE_URL=$MIIIFY_BASE_URL"
    log_info "  OUTPUT_DIR=$OUTPUT_DIR"

    local compose_up_args="-d"
    if [ "$FORCE_PULL" = true ]; then
        compose_up_args="$compose_up_args --pull always"
        log_info "Force pulling latest Docker images..."
    fi
    $DOCKER_COMPOSE_CMD up $compose_up_args
    
    if [ $? -ne 0 ]; then
        log_error "Failed to start services"
        return 1
    fi
    
    log_success "All services started"
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 8
    
    # Verify Miiify base-url configuration
    log_info "Verifying Miiify configuration..."
    local miiify_cmd=$(docker inspect iiif-miiify --format='{{.Config.Cmd}}' 2>/dev/null || echo "")
    if [[ "$miiify_cmd" == *"$MIIIFY_BASE_URL"* ]]; then
        log_success "Miiify base-url correctly set to: $MIIIFY_BASE_URL"
    else
        log_warning "Miiify base-url may not be set correctly. Command: $miiify_cmd"
    fi
    
    # Show service status
    log_info "Service status:"
    $DOCKER_COMPOSE_CMD ps
    
    return 0
}

# Function to show status
show_status() {
    log_info "Service Status:"
    log_info "============================================"
    $DOCKER_COMPOSE_CMD ps
    log_info "============================================"
    
    # Check individual services
    for service in iipimage quickwit annosearch miiify nginx; do
        if docker ps --format '{{.Names}}' | grep -q "iiif-${service}"; then
            log_success "${service}: Running"
        else
            log_warning "${service}: Not running"
        fi
    done
    
    log_info "============================================"
}

# Function to stop services
stop_services() {
    log_info "Stopping all services..."
    
    # Stop main docker-compose services
    $DOCKER_COMPOSE_CMD down 2>/dev/null || true
    
    log_success "Services stopped"
}

# Function to show logs
show_logs() {
    log_info "Showing service logs (Ctrl+C to exit)..."
    $DOCKER_COMPOSE_CMD logs -f
}

# Function to clean output
clean_output() {
    log_warning "This will stop all services and remove the output directory"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        stop_services
        
        if [ -d "$OUTPUT_DIR" ]; then
            log_info "Removing output directory: $OUTPUT_DIR"
            rm -rf "$OUTPUT_DIR"
            log_success "Output directory removed"
        fi
    else
        log_info "Clean cancelled"
    fi
}

# Function to enable maintenance mode
enable_maintenance() {
    log_warning "Enabling maintenance mode..."
    log_info "This will stop all services and show a maintenance page"
    
    # Stop all services
    stop_services
    
    # Start maintenance mode using nginx/docker-compose.maintenance.yml
    log_info "Starting maintenance mode..."
    docker compose -f nginx/docker-compose.maintenance.yml up -d
    
    if [ $? -ne 0 ]; then
        log_error "Failed to start maintenance mode"
        return 1
    fi
    
    log_success "Maintenance mode enabled"
    log_info "Maintenance page available at http://localhost:8080"
    log_info "To bring services back online, run: ./bootstrap.sh build --input-dir <path>"
    return 0
}

# Main execution
main() {
    parse_arguments "$@"
    check_dependencies
    
    # Convert paths to absolute paths (required for Docker volume mounts)
    if [ -n "$INPUT_DIR" ]; then
        INPUT_DIR="$(cd "$INPUT_DIR" && pwd)" || {
            log_error "Invalid input directory: $INPUT_DIR"
            exit 1
        }
    fi
    
    # Convert OUTPUT_DIR to absolute path, creating it if it doesn't exist
    mkdir -p "$OUTPUT_DIR"
    OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
    
    case "$COMMAND" in
        build)
            build_project
            ;;
        status)
            show_status
            ;;
        stop)
            stop_services
            ;;
        restart)
            stop_services
            start_all_services
            ;;
        logs)
            show_logs
            ;;
        clean)
            clean_output
            ;;
        maintenance)
            enable_maintenance
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
