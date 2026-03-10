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
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default configuration
DEFAULT_OUTPUT_DIR="./output"
DEFAULT_HOSTNAME="http://localhost:8080"
DOCKER_COMPOSE_CMD="docker compose"

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
                               (default: http://localhost:8080)
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
  $0 build -i ~/domesday-in-a-box --hostname http://192.168.1.100:8080
  
  # Check service status
  $0 status
  
  # View logs
  $0 logs
  
  # Stop all services
  $0 stop
  
  # Clean everything (stop services, remove output)
  $0 clean

Input Directory Structure:
  <input-dir>/
  ├── config.yml          # Project configuration (required)
  ├── images/             # Source images (optional)
  │   ├── image1.jpg
  │   └── image2.jpg
  └── annotations/        # W3C Web Annotations (optional)
      ├── canvas-1/
      │   ├── annotation-1.json
      │   └── annotation-2.json
      └── canvas-2/
          └── annotation-3.json

Output Directory Structure:
  <output-dir>/
  ├── miiify/
  │   ├── git_store/      # Miiify git storage
  │   └── pack_store/     # Miiify pack storage (served)
  ├── web/
  │   ├── iiif/           # Generated IIIF manifests
  │   ├── pages/          # Generated HTML pages
  │   └── images/         # Processed images
  └── logs/               # Service logs

EOF
}

# Function to parse command line arguments
parse_arguments() {
    INPUT_DIR=""
    OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
    HOSTNAME="$DEFAULT_HOSTNAME"
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
    
    log_success "Annotation structure validation passed"
    return 0
}

# Detect if flat files use dash-separated hierarchical naming
# Returns the hierarchy depth (number of common dash-separated segments before the unique part)
detect_dash_hierarchy() {
    local images_dir="$1"
    
    # Get first few image files
    local sample_files=($(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | head -5))
    
    if [ ${#sample_files[@]} -eq 0 ]; then
        echo "0"
        return
    fi
    
    # Extract basenames without extensions
    local basenames=()
    for file in "${sample_files[@]}"; do
        local basename=$(basename "$file")
        basenames+=("${basename%.*}")
    done
    
    # Count dashes in first file to determine max possible depth
    local first_basename="${basenames[0]}"
    local dash_count=$(echo "$first_basename" | tr -cd '-' | wc -c)
    
    if [ "$dash_count" -eq 0 ]; then
        echo "0"
        return
    fi
    
    # Check each level of dashes to find common prefix
    local max_common_depth=0
    for ((depth=1; depth<=dash_count; depth++)); do
        # Get the prefix up to the Nth dash
        local first_prefix=$(echo "$first_basename" | cut -d'-' -f1-$depth)
        
        # Check if all files share this prefix
        local all_match=true
        for basename in "${basenames[@]}"; do
            local this_prefix=$(echo "$basename" | cut -d'-' -f1-$depth)
            if [ "$this_prefix" != "$first_prefix" ]; then
                all_match=false
                break
            fi
        done
        
        if [ "$all_match" = true ]; then
            max_common_depth=$depth
        else
            break
        fi
    done
    
    echo "$max_common_depth"
}

# Generate collection structure from dash-separated flat files
# E.g., domesday-lincolnshire-0680.tif → domesday.json (Collection) → lincolnshire.json (Manifest)
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
    
    # Extract collection and manifest names from first file
    local first_file=$(basename "${all_files[0]}")
    local first_basename="${first_file%.*}"
    
    # For depth 2: domesday-lincolnshire-0680 → collection=domesday, manifest=lincolnshire
    local collection_name=$(echo "$first_basename" | cut -d'-' -f1)
    local manifest_name=$(echo "$first_basename" | cut -d'-' -f2)
    
    log_info "Generating Collection: $collection_name, Manifest: $manifest_name"
    
    # Generate manifest first
    local manifest_path="${OUTPUT_DIR}/web/iiif/${manifest_name}.json"
    local canvases_json=""
    local canvas_count=0
    
    for image_file in "${all_files[@]}"; do
        local image_basename=$(basename "$image_file")
        local image_name="${image_basename%.*}"
        ((canvas_count++))
        
        # Convert dashes to slashes for Canvas ID
        local canvas_id=$(echo "$image_name" | tr '-' '/')
        
        # Get image dimensions
        local width=3000
        local height=2000
        if command -v identify &> /dev/null; then
            local dims=$(identify -format "%w %h" "$image_file" 2>/dev/null || echo "3000 2000")
            width=$(echo "$dims" | awk '{print $1}')
            height=$(echo "$dims" | awk '{print $2}')
        fi
        
        # Add to canvases
        [ $canvas_count -gt 1 ] && canvases_json+=","
        canvases_json+=$(cat << CANVAS_EOF

    {
      "id": "${hostname}/iiif/canvas/${canvas_id}",
      "type": "Canvas",
      "label": { "en": ["${canvas_id##*/}"] },
      "height": ${height},
      "width": ${width},
      "items": [
        {
          "id": "${hostname}/iiif/canvas/${canvas_id}/page/1",
          "type": "AnnotationPage",
          "items": [
            {
              "id": "${hostname}/iiif/canvas/${canvas_id}/page/1/annotation/1",
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
                    "type": "ImageService2",
                    "profile": "level1"
                  }
                ]
              },
              "target": "${hostname}/iiif/canvas/${canvas_id}"
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
    
    # Create Manifest
    cat > "$manifest_path" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${manifest_name}.json",
  "type": "Manifest",
  "label": {
    "en": ["$(echo $manifest_name | sed 's/.*/\u&/')"]
  },
  "summary": {
    "en": ["${project_description}"]
  },
  "items": [${canvases_json}
  ]
}
EOF
    
    log_success "Generated Manifest with ${canvas_count} canvas(es): ${manifest_path}"
    
    # Generate Collection containing the Manifest
    local collection_path="${OUTPUT_DIR}/web/iiif/${collection_name}.json"
    cat > "$collection_path" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${collection_name}.json",
  "type": "Collection",
  "label": {
    "en": ["$(echo $collection_name | sed 's/.*/\u&/')"]
  },
  "summary": {
    "en": ["${project_title}"]
  },
  "items": [
    {
      "id": "${hostname}/iiif/${manifest_name}.json",
      "type": "Manifest",
      "label": {
        "en": ["$(echo $manifest_name | sed 's/.*/\u&/')"]
      }
    }
  ],
  "service": [
    {
      "id": "${hostname}/annosearch/${collection_name}/search",
      "type": "SearchService2",
      "service": [
        {
          "id": "${hostname}/annosearch/${collection_name}/autocomplete",
          "type": "AutoCompleteService2"
        }
      ]
    }
  ]
}
EOF
    
    log_success "Generated Collection: ${collection_path}"
    
    # Set MANIFEST_NAME and VIEWER_MANIFEST for later use
    export MANIFEST_NAME="$collection_name"
    export VIEWER_MANIFEST="${collection_name}.json"
}

# Function to generate IIIF manifest for a project
generate_manifest() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    local input_dir="$5"
    
    log_info "Generating IIIF manifest for project: $project_name"
    
    # Directory structure determines IIIF hierarchy (images are copied as-is):
    # - Flat (no subdirs) = Single Manifest with all images as Canvases
    # - 1 level (e.g., chapter1/) = Collection with Manifest per directory
    # - 2+ levels (e.g., volume1/chapter1/) = Nested Collections + Manifests
    #
    # Naming strategy:
    # - Flat structure uses project_name from config.yml
    # - Subdirectories: first directory name becomes collection/manifest name
    # - Canvas IDs match the relative file path (without extension)
    
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
        log_info "Detected subdirectory structure - generating Collection with multiple Manifests"
        generate_collection_with_manifests "$project_name" "$project_title" "$project_description" "$hostname" "$input_dir"
    else
        # Check if flat files have dash-separated hierarchical naming
        local hierarchy_depth=$(detect_dash_hierarchy "$images_dir")
        if [ "$hierarchy_depth" -ge 2 ]; then
            log_info "Detected dash-separated hierarchical naming (depth: $hierarchy_depth) - generating Collection structure"
            generate_collection_from_dashed_files "$project_name" "$project_title" "$project_description" "$hostname" "$input_dir" "$hierarchy_depth"
        else
            log_info "Detected flat structure - generating single Manifest"
            generate_single_manifest "$project_name" "$project_title" "$project_description" "$hostname" "$input_dir"
        fi
    fi
}

# Generate a single manifest (for flat image directory)
generate_single_manifest() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    local input_dir="$5"
    
    # For flat structure, use project name from config
    local manifest_name="$project_name"
    
    local manifest_path="${OUTPUT_DIR}/web/iiif/${manifest_name}.json"
    local images_dir="${OUTPUT_DIR}/web/images"
    local canvases_json=""
    local canvas_count=0
    
    # Process each image as a Canvas
    if [ -d "$images_dir" ]; then
        for image_file in $(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort); do
            local image_basename=$(basename "$image_file")
            local image_name="${image_basename%.*}"
            ((canvas_count++))
            
            # Get image dimensions
            local width=3000
            local height=2000
            if command -v identify &> /dev/null; then
                local dims=$(identify -format "%w %h" "$image_file" 2>/dev/null || echo "3000 2000")
                width=$(echo "$dims" | awk '{print $1}')
                height=$(echo "$dims" | awk '{print $2}')
            fi
            
            # Add to canvases
            [ $canvas_count -gt 1 ] && canvases_json+=","
            canvases_json+=$(cat << CANVAS_EOF

    {
      "id": "${hostname}/iiif/canvas/${image_name}",
      "type": "Canvas",
      "label": { "en": ["${image_name}"] },
      "height": ${height},
      "width": ${width},
      "items": [
        {
          "id": "${hostname}/iiif/canvas/${image_name}/page/1",
          "type": "AnnotationPage",
          "items": [
            {
              "id": "${hostname}/iiif/canvas/${image_name}/page/1/annotation/1",
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
                    "type": "ImageService2",
                    "profile": "level1"
                  }
                ]
              },
              "target": "${hostname}/iiif/canvas/${image_name}"
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
    
    # Create single Manifest with all Canvases
    cat > "$manifest_path" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${manifest_name}.json",
  "type": "Manifest",
  "label": {
    "en": ["${project_title}"]
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
  ]
}
EOF
    
    log_success "Generated single Manifest with ${canvas_count} canvas(es): ${manifest_path}"
}

# Helper: Check if directory has subdirectories containing images
has_subdirectories_with_images() {
    local dir="$1"
    if find "$dir" -mindepth 2 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | head -1 | grep -q .; then
        return 0  # Has nested images
    else
        return 1  # No nested images
    fi
}

# Generate collection with multiple manifests (for subdirectory structure)
generate_collection_with_manifests() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    local input_dir="$5"
    
    local images_dir="${OUTPUT_DIR}/web/images"
    
    # Count first-level directories
    local dir_count=$(find "$images_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
    local first_subdir=$(find "$images_dir" -mindepth 1 -maxdepth 1 -type d | sort | head -1)
    
    # If there's only one first-level directory with subdirectories, use it directly as the collection
    if [ "$dir_count" -eq 1 ] && [ -n "$first_subdir" ] && has_subdirectories_with_images "$first_subdir"; then
        local collection_name=$(basename "$first_subdir")
        log_info "Single top-level directory detected, using '$collection_name' as collection"
        # For single top-level, we want lincolnshire.json, not domesday-lincolnshire.json
        # So we call with empty prefix
        generate_simple_nested_collection "$first_subdir" "$collection_name" "${collection_name}.json" "$hostname" "$project_title" "$project_description"
        return 0
    fi
    
    # Multiple first-level directories or flat structure - create wrapping collection
    local collection_name="$project_name"
    if [ -n "$first_subdir" ]; then
        collection_name=$(basename "$first_subdir")
    fi
    
    local collection_path="${OUTPUT_DIR}/web/iiif/${collection_name}.json"
    local items_json=""
    local item_count=0
    
    # Process each subdirectory - could be a Manifest or nested Collection
    for subdir in $(find "$images_dir" -mindepth 1 -maxdepth 1 -type d | sort); do
        local subdir_name=$(basename "$subdir")
        ((item_count++))
        
        # Check if this subdirectory has nested subdirectories with images
        if has_subdirectories_with_images "$subdir"; then
            # Create a nested Collection
            local collection_filename="${subdir_name}.json"
            generate_nested_collection "$subdir" "$subdir_name" "$collection_filename" "$hostname"
            
            # Add to items
            [ $item_count -gt 1 ] && items_json+=","
            items_json+=$(cat << ITEM_EOF

    {
      "id": "${hostname}/iiif/${collection_filename}",
      "type": "Collection",
      "label": { "en": ["${subdir_name}"] }
    }
ITEM_EOF
)
        else
            # Create a Manifest for this subdirectory
            local manifest_path="${OUTPUT_DIR}/web/iiif/${subdir_name}.json"
        local canvases_json=""
        local canvas_count=0
        
        # Process images in this subdirectory
        for image_file in $(find "$subdir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort); do
            local image_basename=$(basename "$image_file")
            local image_name="${image_basename%.*}"
            # Relative path from images_dir (e.g., "chapter1/page001")
            local rel_path="${subdir_name}/${image_name}"
            # Container name for Miiify (convert / to -)
            local container_name=$(echo "$rel_path" | tr '/' '-')
            ((canvas_count++))
            
            # Get image dimensions
            local width=3000
            local height=2000
            if command -v identify &> /dev/null; then
                local dims=$(identify -format "%w %h" "$image_file" 2>/dev/null || echo "3000 2000")
                width=$(echo "$dims" | awk '{print $1}')
                height=$(echo "$dims" | awk '{print $2}')
            fi
            
            # Relative path for image file in IIPImage
            local image_rel_path="${subdir_name}/${image_basename}"
            
            # Add to canvases
            [ $canvas_count -gt 1 ] && canvases_json+=","
            canvases_json+=$(cat << CANVAS_EOF

    {
      "id": "${hostname}/iiif/canvas/${rel_path}",
      "type": "Canvas",
      "label": { "en": ["${image_name}"] },
      "height": ${height},
      "width": ${width},
      "items": [
        {
          "id": "${hostname}/iiif/canvas/${rel_path}/page/1",
          "type": "AnnotationPage",
          "items": [
            {
              "id": "${hostname}/iiif/canvas/${rel_path}/page/1/annotation/1",
              "type": "Annotation",
              "motivation": "painting",
              "body": {
                "id": "${hostname}/iiif/${image_rel_path}/full/max/0/default.jpg",
                "type": "Image",
                "format": "image/jpeg",
                "height": ${height},
                "width": ${width},
                "service": [
                  {
                    "id": "${hostname}/iiif/${image_rel_path}",
                    "type": "ImageService2",
                    "profile": "level1"
                  }
                ]
              },
              "target": "${hostname}/iiif/canvas/${rel_path}"
            }
          ]
        }
      ],
      "annotations": [
        {
          "id": "${hostname}/miiify/${container_name}/?page=0",
          "type": "AnnotationPage"
        }
      ]
    }
CANVAS_EOF
)
        done
        
        # Create manifest for this subdirectory
        cat > "$manifest_path" << MANIFEST_EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${subdir_name}.json",
  "type": "Manifest",
  "label": {
    "en": ["${subdir_name}"]
  },
  "items": [${canvases_json}
  ]
}
MANIFEST_EOF
        
            # Add to collection items
            [ $item_count -gt 1 ] && items_json+=","
            items_json+=$(cat << ITEM_EOF

    {
      "id": "${hostname}/iiif/${subdir_name}.json",
      "type": "Manifest",
      "label": { "en": ["${subdir_name}"] }
    }
ITEM_EOF
)
        fi
    done
    
    # Create the collection
    cat > "$collection_path" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${collection_name}.json",
  "type": "Collection",
  "label": {
    "en": ["${project_title}"]
  },
  "summary": {
    "en": ["${project_description}"]
  },
  "items": [${items_json}
  ],
  "service": [
    {
      "id": "${hostname}/annosearch/${collection_name}/search",
      "type": "SearchService2",
      "service": [
        {
          "id": "${hostname}/annosearch/${collection_name}/autocomplete",
          "type": "AutoCompleteService2"
        }
      ]
    }
  ]
}
EOF
    
    log_success "Generated Collection with ${item_count} item(s): ${collection_path}"
}

# Generate simple nested collection (for single top-level directory)
# Creates manifests with simple names, not prefixed with parent directory
# $1: subdirectory path (e.g., output/web/images/domesday/)
# $2: collection name (e.g., "domesday")
# $3: collection filename (e.g., "domesday.json")
# $4: hostname
# $5: project title
# $6: project description
generate_simple_nested_collection() {
    local subdir_path="$1"
    local collection_name="$2"
    local collection_filename="$3"
    local hostname="$4"
    local project_title="$5"
    local project_description="$6"
    
    local collection_path="${OUTPUT_DIR}/web/iiif/${collection_filename}"
    local items_json=""
    local item_count=0
    
    # Process each subdirectory within this directory
    for nested_dir in $(find "$subdir_path" -mindepth 1 -maxdepth 1 -type d | sort); do
        local nested_name=$(basename "$nested_dir")
        ((item_count++))
        
        # Check if this has further nesting
        if has_subdirectories_with_images "$nested_dir"; then
            # Create another nested Collection with simple name
            local nested_collection_filename="${nested_name}.json"
            generate_simple_nested_collection "$nested_dir" "$nested_name" "$nested_collection_filename" "$hostname" "$project_title" "$project_description"
            
            # Add to items
            [ $item_count -gt 1 ] && items_json+=","
            items_json+=$(cat << ITEM_EOF

    {
      "id": "${hostname}/iiif/${nested_collection_filename}",
      "type": "Collection",
      "label": { "en": ["${nested_name}"] }
    }
ITEM_EOF
)
        else
            # Create a Manifest for this directory with simple name
            local manifest_filename="${nested_name}.json"
            generate_manifest_for_subdir "$nested_dir" "$nested_name" "$manifest_filename" "$hostname"
            
            # Add to items
            [ $item_count -gt 1 ] && items_json+=","
            items_json+=$(cat << ITEM_EOF

    {
      "id": "${hostname}/iiif/${manifest_filename}",
      "type": "Manifest",
      "label": { "en": ["${nested_name}"] }
    }
ITEM_EOF
)
        fi
    done
    
    # Create the collection JSON
    cat > "$collection_path" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${collection_filename}",
  "type": "Collection",
  "label": {
    "en": ["${project_title}"]
  },
  "summary": {
    "en": ["${project_description}"]
  },
  "items": [${items_json}
  ],
  "service": [
    {
      "id": "${hostname}/annosearch/${collection_name}/search",
      "type": "SearchService2",
      "service": [
        {
          "id": "${hostname}/annosearch/${collection_name}/autocomplete",
          "type": "AutoCompleteService2"
        }
      ]
    }
  ]
}
EOF
    
    log_success "Generated Collection '${collection_name}' with ${item_count} item(s)"
}

# Generate a nested collection for a subdirectory (with path prefixes)
# Used for multiple top-level directories
# $1: subdirectory path
# $2: subdirectory name (for labeling)
# $3: collection filename
# $4: hostname
generate_nested_collection() {
    local subdir_path="$1"
    local subdir_name="$2"
    local collection_filename="$3"
    local hostname="$4"
    
    local collection_path="${OUTPUT_DIR}/web/iiif/${collection_filename}"
    local items_json=""
    local item_count=0
    
    # Process each subdirectory within this directory
    for nested_dir in $(find "$subdir_path" -mindepth 1 -maxdepth 1 -type d | sort); do
        local nested_name=$(basename "$nested_dir")
        local path_parts="${subdir_name}-${nested_name}"
        ((item_count++))
        
        # Check if this has further nesting
        if has_subdirectories_with_images "$nested_dir"; then
            # Create another nested Collection
            local nested_collection_filename="${path_parts}.json"
            generate_nested_collection "$nested_dir" "$path_parts" "$nested_collection_filename" "$hostname"
            
            # Add to items
            [ $item_count -gt 1 ] && items_json+=","
            items_json+=$(cat << ITEM_EOF

    {
      "id": "${hostname}/iiif/${nested_collection_filename}",
      "type": "Collection",
      "label": { "en": ["${nested_name}"] }
    }
ITEM_EOF
)
        else
            # Create a Manifest for this directory
            local manifest_filename="${path_parts}.json"
            generate_manifest_for_subdir "$nested_dir" "$path_parts" "$manifest_filename" "$hostname"
            
            # Add to items
            [ $item_count -gt 1 ] && items_json+=","
            items_json+=$(cat << ITEM_EOF

    {
      "id": "${hostname}/iiif/${manifest_filename}",
      "type": "Manifest",
      "label": { "en": ["${nested_name}"] }
    }
ITEM_EOF
)
        fi
    done
    
    # Create the nested collection JSON
    cat > "$collection_path" << EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${collection_filename}",
  "type": "Collection",
  "label": {
    "en": ["${subdir_name}"]
  },
  "items": [${items_json}
  ]
}
EOF
    
    log_info "Generated nested Collection for '${subdir_name}' with ${item_count} item(s)"
}

# Generate a manifest for a specific subdirectory (handles nested paths)
# $1: directory path
# $2: path parts (e.g., "volume1-chapter1")
# $3: manifest filename
# $4: hostname
generate_manifest_for_subdir() {
    local dir_path="$1"
    local path_parts="$2"
    local manifest_filename="$3"
    local hostname="$4"
    
    local manifest_path="${OUTPUT_DIR}/web/iiif/${manifest_filename}"
    local canvases_json=""
    local canvas_count=0
    
    # Get the relative path from images directory
    local images_dir="${OUTPUT_DIR}/web/images"
    local rel_dir_path="${dir_path#$images_dir/}"
    
    # Process all images in this directory (recursively to handle any depth)
    for image_file in $(find "$dir_path" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort); do
        local image_basename=$(basename "$image_file")
        local image_name="${image_basename%.*}"
        
        # Get relative path from images dir for this specific image
        local image_rel_path="${image_file#$images_dir/}"
        local image_rel_dir=$(dirname "$image_rel_path")
        local canvas_rel_path="${image_rel_dir}/${image_name}"
        # Container name for Miiify (convert / to -)
        local container_name=$(echo "$canvas_rel_path" | tr '/' '-')
        ((canvas_count++))
        
        # Get image dimensions
        local width=3000
        local height=2000
        if command -v identify &> /dev/null; then
            local dims=$(identify -format "%w %h" "$image_file" 2>/dev/null || echo "3000 2000")
            width=$(echo "$dims" | awk '{print $1}')
            height=$(echo "$dims" | awk '{print $2}')
        fi
        
        # Add to canvases
        [ $canvas_count -gt 1 ] && canvases_json+=","
        canvases_json+=$(cat << CANVAS_EOF

    {
      "id": "${hostname}/iiif/canvas/${canvas_rel_path}",
      "type": "Canvas",
      "label": { "en": ["${image_name}"] },
      "height": ${height},
      "width": ${width},
      "items": [
        {
          "id": "${hostname}/iiif/canvas/${canvas_rel_path}/page/1",
          "type": "AnnotationPage",
          "items": [
            {
              "id": "${hostname}/iiif/canvas/${canvas_rel_path}/page/1/annotation/1",
              "type": "Annotation",
              "motivation": "painting",
              "body": {
                "id": "${hostname}/iiif/${image_rel_path}/full/max/0/default.jpg",
                "type": "Image",
                "format": "image/jpeg",
                "height": ${height},
                "width": ${width},
                "service": [
                  {
                    "id": "${hostname}/iiif/${image_rel_path}",
                    "type": "ImageService2",
                    "profile": "level1"
                  }
                ]
              },
              "target": "${hostname}/iiif/canvas/${canvas_rel_path}"
            }
          ]
        }
      ],
      "annotations": [
        {
          "id": "${hostname}/miiify/${container_name}/?page=0",
          "type": "AnnotationPage"
        }
      ]
    }
CANVAS_EOF
)
    done
    
    # Create manifest
    cat > "$manifest_path" << MANIFEST_EOF
{
  "@context": "http://iiif.io/api/presentation/3/context.json",
  "id": "${hostname}/iiif/${manifest_filename}",
  "type": "Manifest",
  "label": {
    "en": ["${path_parts}"]
  },
  "items": [${canvases_json}
  ]
}
MANIFEST_EOF
    
    log_info "Generated Manifest for '${path_parts}' with ${canvas_count} canvas(es)"
}

# Function to generate HTML viewer page from template
generate_viewer_page() {
    local page_name="$1"
    local manifest_name="$2"
    local project_title="$3"
    local project_description="$4"
    local hostname="$5"
    
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
        "$template_path" > "$page_path"
    
    log_success "Generated viewer page: ${page_path}"
    log_info "View at: ${hostname}/pages/${page_name}.html"
}

# Function to setup web content
setup_web_content() {
    log_info "Setting up web content..."
    
    # Copy static template files to output
    cp templates/index.html "${OUTPUT_DIR}/web/"
    cp templates/maintenance.html "${OUTPUT_DIR}/web/"
    
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
    log_info "============================================"
    log_info "IIIF-in-a-Box Build Process"
    log_info "============================================"
    log_info "Input Directory:  $INPUT_DIR"
    log_info "Output Directory: $OUTPUT_DIR"
    log_info "Hostname:         $HOSTNAME"
    log_info "============================================"
    
    # Step 0: Stop any running services to avoid lock file issues
    log_info "Stopping any running services (including maintenance mode)..."
    stop_services
    
    # Also stop maintenance mode if it's running
    docker compose -f nginx/docker-compose.maintenance.yml down 2>/dev/null || true
    
    # Step 1: Validate input directory
    if ! validate_input_directory "$INPUT_DIR"; then
        log_error "Input directory validation failed"
        exit 1
    fi
    
    # Step 2: Read configuration
    if ! read_project_config "$INPUT_DIR"; then
        log_error "Failed to read project configuration"
        exit 1
    fi
    
    log_info "============================================"
    log_info "Project: $PROJECT_NAME"
    log_info "Title: $PROJECT_TITLE"
    log_info "============================================"
    
    # Step 2.5: Auto-detect project change and clean if needed
    LAST_PROJECT_FILE="$OUTPUT_DIR/.project"
    if [ -f "$LAST_PROJECT_FILE" ]; then
        LAST_PROJECT=$(cat "$LAST_PROJECT_FILE" 2>/dev/null || echo "")
        if [ -n "$LAST_PROJECT" ] && [ "$LAST_PROJECT" != "$PROJECT_NAME" ]; then
            log_warning "Detected project change: '$LAST_PROJECT' → '$PROJECT_NAME'"
            log_info "Cleaning output directory to prevent mixed content..."
            rm -rf "$OUTPUT_DIR"/{miiify,web,annosearch,logs} 2>/dev/null || true
            log_success "Output directory cleaned"
        fi
    fi
    
    # Step 3: Validate annotation naming
    if ! validate_annotation_naming "$INPUT_DIR"; then
        log_error "Annotation naming validation failed"
        exit 1
    fi
    
    # Step 4: Create output directory structure
    log_info "Creating output directory structure..."
    mkdir -p "$OUTPUT_DIR"/{miiify/{git_store,pack_store},web/{iiif,pages,images},annosearch/qwdata,logs}
    
    # Step 5: Process images
    if ! process_images "$INPUT_DIR" "$OUTPUT_DIR" "$PROJECT_NAME"; then
        log_error "Image processing failed"
        exit 1
    fi
    
    # Step 6: Run Miiify workflow (import → compile)
    if ! miiify_full_workflow "$INPUT_DIR" "$OUTPUT_DIR" "$HOSTNAME"; then
        log_error "Miiify workflow failed"
        exit 1
    fi
    
    # Step 7: Generate IIIF manifests
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
    
    # Page uses project name, but loads the derived manifest
    if ! generate_viewer_page "$PROJECT_NAME" "$VIEWER_MANIFEST" "$PROJECT_TITLE" "$PROJECT_DESCRIPTION" "$HOSTNAME"; then
        log_error "Page generation failed"
        exit 1
    fi
    
    # Step 9: Setup web content
    setup_web_content
    
    # Step 10: Create Docker network
    create_docker_network
    
    # Step 10.5: Prepare Tamerlane image
    if ! prepare_tamerlane_image; then
        log_error "Failed to prepare Tamerlane image"
        exit 1
    fi
    
    # Step 11: Start all services
    if ! start_all_services; then
        log_error "Failed to start all services"
        exit 1
    fi
    
    # Step 12: Wait for AnnoSearch to be ready
    if ! wait_for_annosearch; then
        log_warning "AnnoSearch not ready, skipping search indexing"
    else
        # Step 13: Create search index and load data
        # Use the derived manifest name for indexing, not the project name
        if create_annosearch_index "$MANIFEST_NAME"; then
            load_annosearch_data "$MANIFEST_NAME" "$HOSTNAME" || log_warning "Failed to load data into AnnoSearch"
        fi
    fi
    
    # Store current project name for future builds
    echo "$PROJECT_NAME" > "$OUTPUT_DIR/.project"
    
    log_info "============================================"
    log_success "Build completed successfully!"
    log_info "============================================"
    log_info "Services:"
    log_info "  - Viewer:      ${HOSTNAME}/pages/${PROJECT_NAME}.html"
    log_info "  - Manifests:   ${HOSTNAME}/iiif/"
    log_info "  - Images:      ${HOSTNAME}/iiif/image/"
    log_info "  - Annotations: ${HOSTNAME}/miiify/"
    log_info "  - Search:      ${HOSTNAME}/annosearch/${MANIFEST_NAME}/search"
    log_info "============================================"
}

# Function to prepare Tamerlane image (pull from ghcr or use local)
prepare_tamerlane_image() {
    local ghcr_image="ghcr.io/tamerlaneviewer/tamerlane:latest"
    local local_image="tamerlane_tamerlane:latest"
    
    log_info "Preparing Tamerlane viewer image..."
    
    # Check if image already exists locally
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
    
    # Export environment variables for docker-compose
    export OUTPUT_DIR
    export PROJECT_NAME
    export MIIIFY_BASE_URL="${HOSTNAME}/miiify"
    export ANNOSEARCH_PUBLIC_URL="${HOSTNAME}/annosearch"
    
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Miiify base URL: $MIIIFY_BASE_URL"
    
    # Start all services using main docker-compose.yml
    log_info "Starting IIIF-in-a-Box services..."
    $DOCKER_COMPOSE_CMD up -d
    
    if [ $? -ne 0 ]; then
        log_error "Failed to start services"
        return 1
    fi
    
    log_success "All services started"
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 8
    
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
