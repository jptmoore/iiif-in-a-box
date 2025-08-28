#!/bin/bash
# Docker Corporate Proxy Configuration Script
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

# Function to create Docker daemon configuration
configure_docker_daemon() {
    local daemon_config="/etc/docker/daemon.json"
    local backup_config="/etc/docker/daemon.json.backup"
    local env=$(detect_environment)
    
    log_info "Configuring Docker daemon for corporate proxy environment..."
    
    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ]; then
        log_error "This script needs to be run as root or with sudo to modify Docker daemon configuration"
        log_info "Usage: sudo ./configure-docker-proxy.sh"
        exit 1
    fi
    
    if [ "$env" = "wsl" ]; then
        log_warning "WSL2 detected - Docker daemon configuration may not be effective"
        log_info "For WSL2/Docker Desktop, consider these alternatives:"
        log_info "1. Configure Docker Desktop settings in Windows"
        log_info "2. Use the build-proxy option: ./bootstrap.sh build-proxy"
        log_info "3. Set environment variables for builds"
        log_info ""
        log_info "Continuing with daemon.json creation for completeness..."
    fi
    
    # Create backup if daemon.json exists
    if [ -f "$daemon_config" ]; then
        log_info "Backing up existing daemon.json..."
        cp "$daemon_config" "$backup_config"
    fi
    
    # Create /etc/docker directory if it doesn't exist
    mkdir -p /etc/docker
    
    # Create daemon.json with insecure registry and TLS skip options
    cat > "$daemon_config" << 'EOF'
{
  "insecure-registries": [
    "registry-1.docker.io",
    "docker.io",
    "index.docker.io"
  ],
  "registry-mirrors": [],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    
    log_success "Docker daemon configuration updated"
    log_info "Configuration saved to: $daemon_config"
    
    # Show the configuration
    log_info "Current daemon.json content:"
    cat "$daemon_config"
}

# Function to configure Docker client for proxy
configure_docker_client() {
    local docker_config_dir="$HOME/.docker"
    local docker_config="$docker_config_dir/config.json"
    local env=$(detect_environment)
    
    log_info "Configuring Docker client..."
    
    # Create .docker directory if it doesn't exist
    mkdir -p "$docker_config_dir"
    
    # Create or update config.json
    if [ -f "$docker_config" ]; then
        log_info "Backing up existing Docker client config..."
        cp "$docker_config" "$docker_config.backup"
    fi
    
    cat > "$docker_config" << 'EOF'
{
  "auths": {},
  "credsStore": "",
  "experimental": "disabled",
  "httpHeaders": {
    "User-Agent": "Docker-Client/20.10.0 (linux)"
  }
}
EOF
    
    log_success "Docker client configuration updated"
    
    if [ "$env" = "wsl" ]; then
        log_info "WSL2 Environment Detected - Additional Recommendations:"
        log_info "==============================================="
        log_info "1. Configure Docker Desktop proxy settings in Windows:"
        log_info "   - Open Docker Desktop"
        log_info "   - Go to Settings > Resources > Proxies"
        log_info "   - Enable manual proxy configuration if needed"
        log_info ""
        log_info "2. Set these environment variables for builds:"
        log_info "   export DOCKER_BUILDKIT=0"
        log_info "   export COMPOSE_DOCKER_CLI_BUILD=0"
        log_info "   export npm_config_strict_ssl=false"
        log_info ""
        log_info "3. Use the proxy-friendly build command:"
        log_info "   ./bootstrap.sh build-proxy"
    fi
}

# Function to configure WSL2-specific environment
configure_wsl2_environment() {
    log_info "Configuring WSL2 environment for Docker builds..."
    
    # Create or update .bashrc/.zshrc with proxy-friendly environment variables
    local shell_rc=""
    if [ -n "$ZSH_VERSION" ]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi
    
    log_info "Adding proxy-friendly environment variables to $shell_rc..."
    
    # Add environment variables if they don't exist
    if ! grep -q "# Docker proxy-friendly settings" "$shell_rc" 2>/dev/null; then
        cat >> "$shell_rc" << 'EOF'

# Docker proxy-friendly settings for corporate environments
export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0
export npm_config_strict_ssl=false
export NODE_TLS_REJECT_UNAUTHORIZED=0
EOF
        log_success "Environment variables added to $shell_rc"
        log_info "Run 'source $shell_rc' or restart your terminal to apply changes"
    else
        log_info "Environment variables already configured in $shell_rc"
    fi
}

# Function to detect environment and handle Docker service
detect_environment() {
    if [ -f "/proc/version" ] && grep -q "microsoft" /proc/version; then
        echo "wsl"
    elif [ -f "/.dockerenv" ]; then
        echo "container"
    elif command -v systemctl &> /dev/null && systemctl is-active --quiet docker 2>/dev/null; then
        echo "systemd"
    else
        echo "other"
    fi
}

# Function to restart Docker service
restart_docker() {
    local env=$(detect_environment)
    
    log_info "Detected environment: $env"
    
    case "$env" in
        "wsl")
            log_warning "WSL2 detected - Docker is managed by Windows Docker Desktop"
            log_info "Please restart Docker Desktop from Windows to apply configuration changes"
            log_info "1. Right-click Docker Desktop icon in Windows system tray"
            log_info "2. Select 'Restart'"
            log_info "3. Wait for Docker to fully restart"
            log_warning "Note: The daemon.json configuration may not apply in WSL2 environment"
            log_info "For WSL2, configure Docker Desktop settings in Windows instead"
            return 0
            ;;
        "systemd")
            log_info "Restarting Docker service using systemd..."
            if systemctl is-active --quiet docker; then
                systemctl restart docker
                sleep 5
                
                if systemctl is-active --quiet docker; then
                    log_success "Docker service restarted successfully"
                else
                    log_error "Docker service failed to restart"
                    return 1
                fi
            else
                log_warning "Docker service is not running. Starting it..."
                systemctl start docker
                sleep 5
                
                if systemctl is-active --quiet docker; then
                    log_success "Docker service started successfully"
                else
                    log_error "Docker service failed to start"
                    return 1
                fi
            fi
            ;;
        "container"|"other")
            log_warning "Cannot restart Docker service in this environment"
            log_info "Please restart Docker manually if needed"
            return 0
            ;;
    esac
}

# Function to test Docker connectivity
test_docker() {
    log_info "Testing Docker connectivity..."
    
    # Test with a simple Alpine image pull
    if docker pull alpine:latest; then
        log_success "Docker connectivity test passed"
        docker rmi alpine:latest 2>/dev/null || true
    else
        log_error "Docker connectivity test failed"
        log_warning "You may need to configure HTTP proxy settings as well"
        return 1
    fi
}

# Function to configure HTTP proxy for Docker (optional)
configure_http_proxy() {
    local systemd_dir="/etc/systemd/system/docker.service.d"
    local proxy_conf="$systemd_dir/http-proxy.conf"
    
    read -p "Do you want to configure HTTP proxy settings? (y/N): " configure_proxy
    
    if [[ $configure_proxy =~ ^[Yy]$ ]]; then
        read -p "Enter HTTP proxy URL (e.g., http://proxy.company.com:8080): " http_proxy_url
        read -p "Enter HTTPS proxy URL (or press Enter to use same as HTTP): " https_proxy_url
        
        if [ -z "$https_proxy_url" ]; then
            https_proxy_url="$http_proxy_url"
        fi
        
        read -p "Enter no_proxy hosts (e.g., localhost,127.0.0.1,.company.com): " no_proxy_hosts
        
        log_info "Configuring HTTP proxy settings..."
        
        # Create systemd override directory
        mkdir -p "$systemd_dir"
        
        # Create proxy configuration
        cat > "$proxy_conf" << EOF
[Service]
Environment="HTTP_PROXY=$http_proxy_url"
Environment="HTTPS_PROXY=$https_proxy_url"
Environment="NO_PROXY=$no_proxy_hosts"
EOF
        
        log_success "HTTP proxy configuration created"
        log_info "Reloading systemd and restarting Docker..."
        
        systemctl daemon-reload
        systemctl restart docker
        
        log_success "Docker proxy configuration complete"
    fi
}

# Function to show current configuration
show_config() {
    log_info "Current Docker Configuration:"
    echo "=================================="
    
    if [ -f "/etc/docker/daemon.json" ]; then
        echo "Docker Daemon Config (/etc/docker/daemon.json):"
        cat /etc/docker/daemon.json
    else
        echo "No Docker daemon configuration found"
    fi
    
    echo ""
    
    if [ -f "/etc/systemd/system/docker.service.d/http-proxy.conf" ]; then
        echo "Docker Proxy Config (/etc/systemd/system/docker.service.d/http-proxy.conf):"
        cat /etc/systemd/system/docker.service.d/http-proxy.conf
    else
        echo "No Docker proxy configuration found"
    fi
    
    echo ""
    echo "Docker Service Status:"
    systemctl status docker --no-pager -l
}

# Function to restore backup
restore_backup() {
    log_info "Restoring backup configuration..."
    
    if [ -f "/etc/docker/daemon.json.backup" ]; then
        cp /etc/docker/daemon.json.backup /etc/docker/daemon.json
        log_success "Daemon configuration restored from backup"
    else
        log_warning "No backup found for daemon.json"
    fi
    
    if [ -f "$HOME/.docker/config.json.backup" ]; then
        cp "$HOME/.docker/config.json.backup" "$HOME/.docker/config.json"
        log_success "Client configuration restored from backup"
    else
        log_warning "No backup found for client config"
    fi
    
    log_info "Restarting Docker service..."
    systemctl restart docker
    log_success "Configuration restored and Docker restarted"
}

# Main function
main() {
    local env=$(detect_environment)
    
    case "${1:-configure}" in
        "configure")
            log_info "Docker Corporate Proxy Configuration"
            log_info "==================================="
            log_info "Detected environment: $env"
            
            if [ "$env" = "wsl" ]; then
                log_warning "WSL2/Docker Desktop environment detected"
                log_info "Using WSL2-optimized configuration..."
                configure_docker_daemon
                configure_docker_client
                configure_wsl2_environment
                restart_docker
                test_docker
                
                log_info ""
                log_info "Next Steps for WSL2:"
                log_info "==================="
                log_info "1. Restart Docker Desktop from Windows"
                log_info "2. Source your shell config: source ~/.zshrc (or ~/.bashrc)"
                log_info "3. Try building with: ./bootstrap.sh build-proxy"
            else
                configure_docker_daemon
                configure_docker_client
                restart_docker
                test_docker
                configure_http_proxy
            fi
            ;;
        "test")
            test_docker
            ;;
        "show")
            show_config
            ;;
        "restore")
            if [ "$EUID" -ne 0 ]; then
                log_error "Restore needs to be run as root or with sudo"
                exit 1
            fi
            restore_backup
            ;;
        "wsl2")
            log_info "WSL2-specific configuration..."
            configure_wsl2_environment
            ;;
        *)
            echo "Usage: $0 [configure|test|show|restore|wsl2]"
            echo ""
            echo "Commands:"
            echo "  configure - Configure Docker for corporate proxy (default)"
            echo "  test      - Test Docker connectivity"
            echo "  show      - Show current Docker configuration"
            echo "  restore   - Restore backup configuration"
            echo "  wsl2      - Configure WSL2-specific environment variables"
            echo ""
            echo "Note: 'configure' and 'restore' commands need sudo privileges"
            echo "      WSL2 users should use 'configure' or 'wsl2' commands"
            exit 1
            ;;
    esac
}

main "$@"
