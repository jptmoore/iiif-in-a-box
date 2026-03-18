#!/bin/bash
# Configuration Helper Functions
# This script contains functions for reading and validating configuration

# Function to check if yq is installed
check_yq_dependency() {
    if ! command -v yq &> /dev/null; then
        log_error "yq is not installed but is required for YAML configuration parsing"
        log_error "Install yq: https://github.com/mikefarah/yq"
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

# Function to validate configuration
validate_config() {
    local input_dir="$1"
    local config_file="${input_dir}/config.yml"
    
    log_info "Validating configuration..."
    
    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check if it's valid YAML (basic check)
    if ! grep -q "^project:" "$config_file"; then
        log_error "Invalid configuration: missing 'project:' section"
        return 1
    fi
    
    # Check for required fields
    local has_name=$(grep -A 10 "^project:" "$config_file" | grep -c "name:")
    if [ "$has_name" -eq 0 ]; then
        log_error "Invalid configuration: missing 'project.name'"
        return 1
    fi
    
    log_success "Configuration is valid"
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

# Function to create default config if needed
create_default_config() {
    local input_dir="$1"
    local project_name="$2"
    local config_file="${input_dir}/config.yml"
    
    if [ -f "$config_file" ]; then
        log_info "Configuration file already exists"
        return 0
    fi
    
    log_info "Creating default configuration..."
    
    cat > "$config_file" << EOF
# IIIF-in-a-Box Project Configuration

project:
  name: ${project_name}
  title: "${project_name^} Collection"
  description: "Explore the ${project_name} collection using our interactive IIIF viewer"
  
  metadata:
    - label:
        en: ["Creator"]
      value:
        none: ["Unknown"]
    - label:
        en: ["Date"]
      value:
        none: ["Unknown"]

provider:
  id: "https://example.org"
  type: "Agent"
  label:
    en: ["Example Organization"]
  homepage:
    - id: "https://example.org"
      type: "Text"
      label:
        en: ["Visit our website"]
      format: "text/html"
EOF
    
    log_success "Default configuration created at $config_file"
    log_warning "Please edit the configuration to add your project details"
}

# Print build summary and embed snippet after a successful build
print_build_summary() {
    local project_name="$1"
    local manifest_name="$2"
    local project_title="$3"
    local hostname="$4"

    log_info "============================================"
    log_success "Build completed successfully!"
    log_info "============================================"
    log_info ""
    log_info "Embed snippet — paste into your static site:"
    echo ""
    echo '<iframe'
    echo "  src=\"${hostname}/viewer/?iiif-content=${hostname}/iiif/${manifest_name}.json\""
    echo '  width="100%" height="600"'
    echo '  style="border:none;"'
    echo "  title=\"${project_title}\""
    echo '  allowfullscreen>'
    echo '</iframe>'
    echo ""
    log_info "An example of the viewer embedded in a static page:"
    log_info "  ${hostname}/pages/${project_name}.html"
    log_info "============================================"
}
