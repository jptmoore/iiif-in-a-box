#!/bin/bash
# IIIF Manifest Generation Helper Functions
#
# Generates IIIF Presentation API 3.0 Collections and Manifests from
# dash-separated flat image filenames. Naming convention:
#   foo-canvas.jpg            → foo.json (Manifest)
#   foo-bar-canvas.jpg        → foo.json (Collection) → bar.json (Manifest)
#   foo-bar-baz-canvas.jpg    → foo.json (Collection) → bar.json (Collection) → baz.json (Manifest)
#
# Depends on log_*, get_config_metadata, get_config_provider,
# extract_annotation_target, and the OUTPUT_DIR / INPUT_DIR globals from
# bootstrap.sh.

# Detect dash-hierarchy depth (number of dashes in the first image's basename).
detect_dash_hierarchy() {
    local images_dir="$1"

    local first_file
    first_file=$(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort | head -1)

    if [ -z "$first_file" ]; then
        echo "0"
        return
    fi

    local first_basename
    first_basename=$(basename "$first_file")
    local name="${first_basename%.*}"

    local dash_count
    dash_count=$(echo "$name" | tr -cd '-' | wc -c)
    echo "$dash_count"
}

# Generate Collection structure from dash-separated flat files.
generate_collection_from_dashed_files() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    local input_dir="$5"
    local hierarchy_depth="$6"

    local images_dir="${OUTPUT_DIR}/web/images"

    local all_files=($(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort))

    if [ ${#all_files[@]} -eq 0 ]; then
        log_error "No image files found"
        return 1
    fi

    local first_file=$(basename "${all_files[0]}")
    local first_basename="${first_file%.*}"
    local collection_name=$(echo "$first_basename" | cut -d'-' -f1)

    log_info "Generating Collection structure for: $collection_name (depth: $hierarchy_depth)"

    local metadata_json=$(get_config_metadata "${input_dir}/config.yml")
    local provider_json=$(get_config_provider "${input_dir}/config.yml")

    build_dashed_collection_recursive "$images_dir" "$collection_name" "$hostname" 1 "$hierarchy_depth" "$metadata_json" "$provider_json"

    export MANIFEST_NAME="$collection_name"
    export VIEWER_MANIFEST="$collection_name"
    export MANIFEST_TYPE="Collection"
}

# Recursively build collections/manifests from dash-separated files.
# $1 images_dir, $2 prefix, $3 hostname, $4 current_depth, $5 max_depth,
# $6 metadata_json, $7 provider_json.
build_dashed_collection_recursive() {
    local images_dir="$1"
    local prefix="$2"
    local hostname="$3"
    local current_depth="$4"
    local max_depth="$5"
    local metadata_json="$6"
    local provider_json="$7"

    local simple_name="${prefix##*-}"
    [ -z "$simple_name" ] && simple_name="$prefix"

    if [ "$current_depth" -eq "$max_depth" ]; then
        build_dashed_manifest "$images_dir" "$prefix" "$simple_name" "$hostname" "$metadata_json" "$provider_json"
        return
    fi

    local children_list=""
    while IFS= read -r -d '' image_file; do
        local basename=$(basename "$image_file")
        local name="${basename%.*}"

        if [[ "$name" == "$prefix-"* ]]; then
            local remainder="${name#$prefix-}"
            local next_segment=$(echo "$remainder" | cut -d'-' -f1)
            children_list="${children_list}${next_segment}"$'\n'
        fi
    done < <(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) -print0)

    local unique_children=$(echo "$children_list" | sort -u)

    local items_json=""
    local item_count=0
    for child in $unique_children; do
        [ -z "$child" ] && continue
        local child_prefix="$prefix-$child"
        local next_depth=$((current_depth + 1))

        build_dashed_collection_recursive "$images_dir" "$child_prefix" "$hostname" "$next_depth" "$max_depth" "$metadata_json" "$provider_json"

        local child_type="Manifest"
        if [ "$next_depth" -lt "$max_depth" ]; then
            child_type="Collection"
        fi

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

    local collection_path="${OUTPUT_DIR}/web/iiif/${simple_name}.json"
    local service_block=""
    local metadata_block=""
    local provider_block=""

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

# Build a Manifest from dash-separated files matching a given prefix.
# $1 images_dir, $2 prefix, $3 simple_name, $4 hostname,
# $5 metadata_json, $6 provider_json.
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

    for image_file in $(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort); do
        local image_basename=$(basename "$image_file")
        local image_name="${image_basename%.*}"

        if [[ "$image_name" == "$prefix-"* ]]; then
            ((canvas_count++))

            # Derive canvas ID from annotation target if available so the manifest
            # canvas ID always matches what annotations reference, regardless of
            # the hostname used when annotations were authored.
            local anno_folder="${INPUT_DIR}/annotations/${image_name}"
            local canvas_key="${image_name##*-}"
            local canvas_id
            local raw_target_source
            raw_target_source=$(extract_annotation_target "$anno_folder" "$canvas_key")

            if [ -n "$raw_target_source" ]; then
                canvas_id="$raw_target_source"
                log_info "Canvas ID from annotation target: $canvas_id"
            else
                local generated_id=$(echo "$image_name" | tr '-' '/')
                canvas_id="${hostname}/${generated_id%/*}/canvas/${generated_id##*/}"
                log_info "Canvas ID generated (no annotations): $canvas_id"
            fi

            local width=3000
            local height=2000
            if command -v identify &> /dev/null; then
                local dims=$(identify -format "%w %h\n" "$image_file" 2>/dev/null | head -1 2>/dev/null || echo "3000 2000")
                width=$(echo "$dims" | awk '{print $1}')
                height=$(echo "$dims" | awk '{print $2}')
            fi

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

# Top-level entry point: choose between single-manifest and collection-of-manifests
# based on the dash-hierarchy depth of the input filenames.
generate_manifest() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    local input_dir="$5"

    log_info "Generating IIIF manifest for project: $project_name"

    mkdir -p "${OUTPUT_DIR}/web/iiif"
    local images_dir="${OUTPUT_DIR}/web/images"

    local has_subdirs=false
    if [ -d "$images_dir" ]; then
        if find "$images_dir" -mindepth 2 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | head -1 | grep -q .; then
            has_subdirs=true
        fi
    fi

    if [ "$has_subdirs" = true ]; then
        log_error "Subdirectory structure not supported - use dash-separated flat files"
        log_error "Example: mybook-page01.jpg, mybook-page02.jpg"
        return 1
    fi

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
}

# Generate a single Manifest from dash-separated files (manifest-canvas pattern).
generate_single_manifest() {
    local project_name="$1"
    local project_title="$2"
    local project_description="$3"
    local hostname="$4"
    local input_dir="$5"

    local images_dir="${OUTPUT_DIR}/web/images"

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

    if [ -d "$images_dir" ]; then
        for image_file in $(find "$images_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | sort); do
            local image_basename=$(basename "$image_file")
            local image_name="${image_basename%.*}"

            ((canvas_count++))

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

            local width=3000
            local height=2000
            if command -v identify &> /dev/null; then
                local dims=$(identify -format "%w %h\n" "$image_file" 2>/dev/null | head -1 2>/dev/null || echo "3000 2000")
                width=$(echo "$dims" | awk '{print $1}')
                height=$(echo "$dims" | awk '{print $2}')
            fi

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

    local metadata_json=$(get_config_metadata "${input_dir}/config.yml")
    local provider_json=$(get_config_provider "${input_dir}/config.yml")

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

    local manifest_label=$(echo "$manifest_name" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

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

    export MANIFEST_NAME="$manifest_name"
    export VIEWER_MANIFEST="$manifest_name"
    export MANIFEST_TYPE="Manifest"
}
