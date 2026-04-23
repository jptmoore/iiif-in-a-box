#!/bin/bash
# Web Content Helper Functions
#
# Renders the static web pages served by nginx: the per-project viewer page
# and the entry index that redirects to it. Depends on log_*, the
# OUTPUT_DIR / PROJECT_NAME / IIIF_VERSION globals, and the templates/
# directory in the workspace.

# Generate an HTML viewer page for a manifest from the page template.
generate_viewer_page() {
    local page_name="$1"
    local manifest_name="$2"
    local project_title="$3"
    local project_description="$4"
    local hostname="$5"
    local manifest_type="${6:-Collection}"

    log_info "Generating viewer page: ${page_name}.html (loading manifest: ${manifest_name}.json)"

    mkdir -p "${OUTPUT_DIR}/web/pages"
    local page_path="${OUTPUT_DIR}/web/pages/${page_name}.html"
    local template_path="templates/pages/_template.html"

    if [ ! -f "$template_path" ]; then
        log_error "Template not found: $template_path"
        return 1
    fi

    # Note: 'demo' in the manifest URL gets replaced with the manifest name.
    sed -e "s/Demo/${project_title}/g" \
        -e "s/demo/${manifest_name}/g" \
        -e "s|https://digitaldomesday.org|${hostname}|g" \
        -e "s/IIIF Collection/IIIF ${manifest_type}/g" \
        "$template_path" > "$page_path"

    log_success "Generated viewer page: ${page_path}"
    log_info "View at: ${hostname}/pages/${page_name}.html"
}

# Stage static templates and a redirect index page into the web output dir.
setup_web_content() {
    log_info "Setting up web content..."

    cp templates/services.html "${OUTPUT_DIR}/web/"
    sed -i "s/__VERSION__/${IIIF_VERSION}/g" "${OUTPUT_DIR}/web/services.html"
    cp templates/maintenance.html "${OUTPUT_DIR}/web/"

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

    if [ -d "assets" ]; then
        cp -r assets "${OUTPUT_DIR}/web/"
        log_info "Copied assets to web directory"
    fi

    log_success "Web content setup complete"
}
