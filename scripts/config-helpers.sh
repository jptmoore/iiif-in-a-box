#!/bin/bash
# Configuration Helper Functions
# This script contains functions for reading and validating configuration

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
