#!/bin/bash
# Configuration Helper Functions
# This script contains functions for reading and validating configuration

# Function to check if yq (mikefarah/yq v4+) is installed
check_yq_dependency() {
    if ! command -v yq &> /dev/null; then
        log_error "yq is not installed but is required for YAML configuration parsing"
        log_error "Install yq: https://github.com/mikefarah/yq"
        log_error "  macOS: brew install yq"
        log_error "  Linux: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
        return 1
    fi
    # Verify it's mikefarah/yq (not the Python kislyuk/yq which has incompatible syntax)
    if ! yq --version 2>&1 | grep -q "mikefarah\|github.com/mikefarah"; then
        log_error "Wrong version of yq detected ($(yq --version 2>&1 | head -1))"
        log_error "This project requires mikefarah/yq v4+, not the Python yq wrapper"
        log_error "Install the correct yq:"
        log_error "  macOS: brew install yq"
        log_error "  Linux: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
        return 1
    fi
    return 0
}

# Function to read project configuration from YAML
read_project_config() {
    local input_dir="$1"
    local config_file="${input_dir}/config.yml"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    log_info "Reading configuration from $config_file"
    
    # Export configuration values as environment variables
    # Using yq or basic grep/sed for parsing (fallback to basic parsing if yq not available)
    
    # Try to extract project name
    PROJECT_NAME=$(grep -A 10 "^project:" "$config_file" | grep "name:" | sed 's/.*name:[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"' | head -1)
    PROJECT_TITLE=$(grep -A 10 "^project:" "$config_file" | grep "title:" | sed 's/.*title:[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"' | head -1)
    PROJECT_DESCRIPTION=$(grep -A 10 "^project:" "$config_file" | grep "description:" | sed 's/.*description:[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"' | head -1)
    
    if [ -z "$PROJECT_NAME" ]; then
        log_error "Project name not found in config file"
        return 1
    fi
    
    export PROJECT_NAME
    export PROJECT_TITLE
    export PROJECT_DESCRIPTION
    
    log_info "Project: $PROJECT_NAME"
    log_info "Title: $PROJECT_TITLE"
    
    # Store config file path for later use
    export CONFIG_FILE="$config_file"
    
    return 0
}

# Function to extract metadata from config.yml as JSON
# Returns IIIF-compliant metadata array
get_config_metadata() {
    local config_file="${CONFIG_FILE:-${1:-config.yml}}"
    
    if [ ! -f "$config_file" ]; then
        echo ""
        return 0
    fi
    
    # Check if metadata exists in config
    if grep -q "metadata:" "$config_file"; then
        # yq is required for metadata extraction
        if ! command -v yq &> /dev/null; then
            log_error "Config contains metadata but yq is not installed" >&2
            return 1
        fi
        
        # Use yq to extract metadata as JSON
        local metadata_json=$(yq -o=json '.project.metadata' "$config_file" 2>/dev/null)
        if [ "$metadata_json" != "null" ] && [ -n "$metadata_json" ]; then
            echo "$metadata_json"
            return 0
        fi
    fi
    
    echo ""
    return 0
}

# Function to extract provider from config.yml as JSON
# Returns IIIF-compliant provider array
get_config_provider() {
    local config_file="${CONFIG_FILE:-${1:-config.yml}}"
    
    if [ ! -f "$config_file" ]; then
        echo ""
        return 0
    fi
    
    # Check if provider exists in config
    if grep -q "provider:" "$config_file"; then
        # yq is required for provider extraction
        if ! command -v yq &> /dev/null; then
            log_error "Config contains provider but yq is not installed" >&2
            return 1
        fi
        
        # Use yq to extract provider as JSON
        local provider_json=$(yq -o=json '.provider' "$config_file" 2>/dev/null)
        if [ "$provider_json" != "null" ] && [ -n "$provider_json" ]; then
            # Wrap in array if it's a single provider object
            if [[ "$provider_json" =~ ^\{ ]]; then
                echo "[$provider_json]"
            else
                echo "$provider_json"
            fi
            return 0
        fi
    fi
    
    echo ""
    return 0
}

# Function to validate input directory structure
validate_input_directory() {
    local input_dir="$1"
    
    log_info "Validating input directory structure..."
    
    # Check if directory exists
    if [ ! -d "$input_dir" ]; then
        log_error "Input directory not found: $input_dir"
        return 1
    fi
    
    # Check for config file
    if [ ! -f "${input_dir}/config.yml" ]; then
        log_error "Missing config.yml in input directory"
        return 1
    fi
    
    # Check for images directory (optional but warn if missing)
    if [ ! -d "${input_dir}/images" ]; then
        log_warning "No images directory found in input directory"
    fi
    
    # Check for annotations directory (optional but warn if missing)
    if [ ! -d "${input_dir}/annotations" ]; then
        log_warning "No annotations directory found in input directory"
    fi
    
    log_success "Input directory structure is valid"
    return 0
}

# Print build summary and embed snippet after a successful build
print_build_summary() {
    local project_name="$1"
    local manifest_name="$2"
    local project_title="$3"
    local hostname="$4"

    echo ""
    log_success "Build completed successfully! (iiif-in-a-box v${IIIF_VERSION})"
    echo ""
    echo "Embed snippet — paste into your static site:"
    echo ""
    echo '<iframe'
    echo "  src=\"${hostname}/viewer/?iiif-content=${hostname}/iiif/${manifest_name}.json\""
    echo '  width="100%" height="600"'
    echo '  style="border:none;"'
    echo "  title=\"${project_title}\""
    echo '  allowfullscreen>'
    echo '</iframe>'
    echo ""
    echo "Example page:  ${hostname}/pages/${project_name}.html"
    echo "Viewer:        ${hostname}/viewer/?iiif-content=${hostname}/iiif/${manifest_name}.json"
    echo ""
}
