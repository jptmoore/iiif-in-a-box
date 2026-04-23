#!/bin/bash
# Smoke Test Helper Functions
#
# Probes a running IIIF-in-a-Box stack for end-to-end correctness.
# Runs every assertion through `docker exec iiif-nginx wget` so the only
# dependency is what's already in the nginx:alpine container (busybox wget,
# grep, file). Tests the production network path, not a mock.
#
# Reads MANIFEST_NAME from $OUTPUT_DIR/.project (set by build_project) when
# not provided explicitly, so `./bootstrap.sh test` works on any prior build.

# Run a single assertion. $1 is the description, $2... is the command.
# The command should exit 0 on success.
_assert() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $desc"
        return 0
    else
        echo -e "  ${RED}✗${NC} $desc"
        return 1
    fi
}

# Fetch a URL from inside iiif-nginx and print response body to stdout.
_nginx_get() {
    docker exec iiif-nginx wget -qO- "$1" 2>/dev/null
}

# Fetch a URL and print the HTTP status line.
_nginx_status() {
    docker exec iiif-nginx wget -S --spider "$1" 2>&1 | grep -oE 'HTTP/[0-9.]+ [0-9]+' | head -1
}

# Fetch a URL via POST and print the HTTP status line.
_nginx_post_status() {
    docker exec iiif-nginx wget -S --spider --post-data='' "$1" 2>&1 | grep -oE 'HTTP/[0-9.]+ [0-9]+' | head -1
}

# Top-level test runner. Returns non-zero if any assertion fails.
run_smoke_tests() {
    local manifest_name="${1:-${MANIFEST_NAME}}"

    if [ -z "$manifest_name" ] && [ -f "${OUTPUT_DIR}/.project" ]; then
        manifest_name=$(cat "${OUTPUT_DIR}/.project")
    fi

    if [ -z "$manifest_name" ]; then
        log_error "No manifest name provided and ${OUTPUT_DIR}/.project not found"
        log_error "Run a build first, or pass the manifest name as the first argument"
        return 1
    fi

    if ! docker ps --format '{{.Names}}' | grep -q '^iiif-nginx$'; then
        log_error "iiif-nginx is not running — start the stack with 'bootstrap.sh build' first"
        return 1
    fi

    echo ""
    echo -e "${BLUE}Running smoke tests against running stack (manifest: ${manifest_name})${NC}"
    echo ""

    local failures=0
    local body status

    # --- Manifest correctness ---
    body=$(_nginx_get "http://nginx/iiif/${manifest_name}.json")
    _assert "manifest /iiif/${manifest_name}.json is reachable" \
        test -n "$body" || ((failures++))
    _assert "manifest declares IIIF Presentation 3 @context" \
        grep -qF 'http://iiif.io/api/presentation/3/context.json' <<< "$body" || ((failures++))
    _assert "manifest is a Manifest or Collection" \
        grep -qE '"type"[[:space:]]*:[[:space:]]*"(Manifest|Collection)"' <<< "$body" || ((failures++))

    # Identify the top-level resource type (first "type" field in the body).
    # A Collection's body also contains "type":"Manifest" for its children, so we
    # cannot just grep the whole body.
    local top_type
    top_type=$(grep -oE '"type"[[:space:]]*:[[:space:]]*"[^"]+"' <<< "$body" | head -1 | grep -oE '"[^"]+"$' | tr -d '"')

    # --- Canvas count matches image count (Manifest only; Collections are recursive) ---
    if [ "$top_type" = "Manifest" ]; then
        local canvas_count image_count
        canvas_count=$(grep -cE '"type"[[:space:]]*:[[:space:]]*"Canvas"' <<< "$body")
        image_count=$(find "${OUTPUT_DIR}/web/images" -maxdepth 1 -type f \
            \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) | wc -l)
        _assert "canvas count ($canvas_count) matches image count ($image_count)" \
            test "$canvas_count" -eq "$image_count" || ((failures++))
    fi

    # --- Image service: pick the first image and probe info.json + a tile ---
    local first_image
    first_image=$(find "${OUTPUT_DIR}/web/images" -maxdepth 1 -type f \
        \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.png" \) \
        | sort | head -1)
    if [ -n "$first_image" ]; then
        local image_basename
        image_basename=$(basename "$first_image")
        body=$(_nginx_get "http://nginx/iiif/${image_basename}/info.json")
        _assert "image info.json /iiif/${image_basename}/info.json reachable" \
            test -n "$body" || ((failures++))
        _assert "image info.json declares ImageService3" \
            grep -qE '"type"[[:space:]]*:[[:space:]]*"ImageService3"' <<< "$body" || ((failures++))

        # Render a small tile and check the bytes are a real JPEG (SOI marker FF D8 FF).
        # nginx:alpine doesn't ship `file`, so we read the first 3 bytes as hex.
        local tile_url="http://nginx/iiif/${image_basename}/full/100,/0/default.jpg"
        local tile_magic
        tile_magic=$(docker exec iiif-nginx sh -c \
            "wget -qO /tmp/tile.jpg '${tile_url}' && head -c 3 /tmp/tile.jpg | od -An -tx1 | tr -d ' \n'" 2>/dev/null)
        if ! _assert "iipimage renders a JPEG tile" \
            test "$tile_magic" = "ffd8ff"; then
            ((failures++))
            local tile_status
            tile_status=$(_nginx_status "$tile_url")
            echo "      url:    $tile_url"
            echo "      status: ${tile_status:-no response}"
            echo "      magic:  ${tile_magic:-empty} (expected ffd8ff)"
        fi
    fi

    # --- Annotation page: pick the first annotation folder and probe miiify ---
    local first_anno_folder
    if [ -n "$INPUT_DIR" ] && [ -d "${INPUT_DIR}/annotations" ]; then
        first_anno_folder=$(find "${INPUT_DIR}/annotations" -mindepth 1 -maxdepth 1 -type d \
            | sort | head -1)
    fi
    if [ -n "$first_anno_folder" ]; then
        local anno_name
        anno_name=$(basename "$first_anno_folder")
        body=$(_nginx_get "http://nginx/miiify/${anno_name}/?page=0")
        _assert "miiify /miiify/${anno_name}/?page=0 reachable" \
            test -n "$body" || ((failures++))
        _assert "miiify response is an AnnotationPage" \
            grep -qE '"type"[[:space:]]*:[[:space:]]*"AnnotationPage"' <<< "$body" || ((failures++))
    fi

    # --- AnnoSearch: structure only; index commit is async so empty results are OK ---
    status=$(_nginx_status "http://nginx/annosearch/${manifest_name}/search?q=test")
    _assert "annosearch /annosearch/${manifest_name}/search returns 200" \
        grep -q ' 200$' <<< "$status" || ((failures++))

    # --- Read-only enforcement ---
    status=$(_nginx_post_status "http://nginx/iiif/${manifest_name}.json")
    _assert "POST to /iiif/ is rejected (read-only)" \
        grep -qE ' (403|405)$' <<< "$status" || ((failures++))

    status=$(_nginx_post_status "http://nginx/miiify/${anno_name:-test}/")
    _assert "POST to /miiify/ is rejected (read-only)" \
        grep -qE ' (403|405)$' <<< "$status" || ((failures++))

    # --- Path traversal guard ---
    status=$(_nginx_status "http://nginx/iiif/foo/../bar")
    _assert "path traversal in /iiif/ returns 400" \
        grep -q ' 400$' <<< "$status" || ((failures++))

    # --- Security headers ---
    local headers
    headers=$(docker exec iiif-nginx wget -S --spider "http://nginx/iiif/${manifest_name}.json" 2>&1)
    _assert "X-Content-Type-Options header present" \
        grep -qi 'X-Content-Type-Options:[[:space:]]*nosniff' <<< "$headers" || ((failures++))
    _assert "Referrer-Policy header present" \
        grep -qi 'Referrer-Policy:' <<< "$headers" || ((failures++))

    # --- CORS: IIIF spec requires Access-Control-Allow-Origin: * on manifests,
    #     image responses, and annotations so external viewers work.
    _assert "CORS header present on manifest" \
        grep -qi 'Access-Control-Allow-Origin:[[:space:]]*\*' <<< "$headers" || ((failures++))
    if [ -n "$first_image" ]; then
        local image_headers
        image_headers=$(docker exec iiif-nginx wget -S --spider \
            "http://nginx/iiif/${image_basename}/info.json" 2>&1)
        _assert "CORS header present on image info.json" \
            grep -qi 'Access-Control-Allow-Origin:[[:space:]]*\*' <<< "$image_headers" || ((failures++))
    fi
    if [ -n "$anno_name" ]; then
        local miiify_headers
        miiify_headers=$(docker exec iiif-nginx wget -S --spider \
            "http://nginx/miiify/${anno_name}/?page=0" 2>&1)
        _assert "CORS header present on miiify annotations" \
            grep -qi 'Access-Control-Allow-Origin:[[:space:]]*\*' <<< "$miiify_headers" || ((failures++))
    fi

    # --- Viewer page ---
    body=$(_nginx_get "http://nginx/pages/${manifest_name}.html")
    _assert "viewer page /pages/${manifest_name}.html reachable" \
        test -n "$body" || ((failures++))
    _assert "viewer page references the manifest" \
        grep -qF "${manifest_name}.json" <<< "$body" || ((failures++))

    echo ""
    if [ $failures -eq 0 ]; then
        log_success "All smoke tests passed"
        return 0
    else
        log_error "${failures} smoke test(s) failed"
        return 1
    fi
}
