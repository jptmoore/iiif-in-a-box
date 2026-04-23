#!/bin/bash
# Service Lifecycle Helper Functions
#
# Manages the Docker network, Tamerlane image preparation, and the
# start/stop/status/logs/clean/maintenance lifecycle of the IIIF stack.
# Depends on log_*, the wait_for_* probes from annosearch-helpers.sh, and
# the OUTPUT_DIR / HOSTNAME / FORCE_PULL / DOCKER_COMPOSE_CMD globals.

# Create the shared external Docker network if it does not exist.
create_docker_network() {
    if ! docker network ls | grep -q "iiif-network"; then
        log_info "Creating shared Docker network..."
        docker network create iiif-network
        log_success "Docker network created"
    else
        log_info "Docker network already exists"
    fi
}

# Pull or re-tag the Tamerlane viewer image so docker-compose can find it.
prepare_tamerlane_image() {
    local ghcr_image="ghcr.io/tamerlaneviewer/tamerlane:latest"
    local local_image="tamerlane_tamerlane:latest"

    log_info "Preparing Tamerlane viewer image..."

    if docker image inspect "$ghcr_image" &> /dev/null; then
        log_info "Tamerlane image already exists locally"
        docker tag "$ghcr_image" "$local_image"
        log_success "Tagged ${ghcr_image} as ${local_image}"
        return 0
    fi

    log_info "Pulling Tamerlane from GitHub Container Registry..."
    if docker pull "$ghcr_image" 2>/dev/null; then
        log_success "Successfully pulled Tamerlane from ghcr.io"
        docker tag "$ghcr_image" "$local_image"
        log_info "Tagged ${ghcr_image} as ${local_image}"
        return 0
    fi

    log_error "Failed to pull Tamerlane from ghcr.io"
    log_error "Image not available - please authenticate with: docker login ghcr.io"
    return 1
}

# Bring up the full stack and verify readiness via external HTTP probes.
start_all_services() {
    log_info "Starting all IIIF services..."

    # Extract port from hostname (default to 80 if not specified)
    if [[ "$HOSTNAME" =~ :([0-9]+)$ ]]; then
        export NGINX_PORT="${BASH_REMATCH[1]}"
    else
        export NGINX_PORT="80"
    fi

    export OUTPUT_DIR
    export PROJECT_NAME
    export MIIIFY_BASE_URL="${HOSTNAME}/miiify"
    export ANNOSEARCH_PUBLIC_URL="${HOSTNAME}/annosearch"

    log_info "Output directory: $OUTPUT_DIR"
    log_info "Nginx port: $NGINX_PORT"
    log_info "Miiify base URL: $MIIIFY_BASE_URL"
    log_info "AnnoSearch public URL: $ANNOSEARCH_PUBLIC_URL"

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
        log_info "Run '$0 logs' to investigate"
        return 1
    fi

    log_success "All containers started"

    # The probes below run via `docker exec iiif-nginx wget ...`, so verify
    # the prober itself is up first — otherwise a broken nginx surfaces as
    # "Quickwit not ready" instead of the real cause.
    if [ "$(docker inspect iiif-nginx --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
        log_error "iiif-nginx container is not running — cannot probe other services"
        log_info "Run '$0 logs' to investigate"
        return 1
    fi

    # Probe every HTTP-speaking service from inside the iiif-nginx container.
    # This works regardless of host port publishing and uses the same network
    # path that production traffic takes — a passing probe means real readiness.
    wait_for_quickwit   || return 1
    wait_for_annosearch || return 1
    wait_for_miiify     || return 1
    wait_for_tamerlane  || return 1
    # iipimage is FastCGI, not HTTP, so it has no direct probe. It is verified
    # transitively when the AnnoSearch indexing step below fetches manifests
    # through nginx — those manifests reference image URLs served by iipimage.
    log_success "All services are ready"

    log_info "Verifying Miiify configuration..."
    local miiify_cmd=$(docker inspect iiif-miiify --format='{{.Config.Cmd}}' 2>/dev/null || echo "")
    if [[ "$miiify_cmd" == *"$MIIIFY_BASE_URL"* ]]; then
        log_success "Miiify base-url correctly set to: $MIIIFY_BASE_URL"
    else
        log_warning "Miiify base-url may not be set correctly. Command: $miiify_cmd"
    fi

    log_info "Service status:"
    $DOCKER_COMPOSE_CMD ps

    return 0
}

# Print the running status of every IIIF service.
show_status() {
    log_info "Service Status:"
    log_info "============================================"
    $DOCKER_COMPOSE_CMD ps
    log_info "============================================"

    for service in iipimage quickwit annosearch miiify nginx; do
        if docker ps --format '{{.Names}}' | grep -q "iiif-${service}"; then
            log_success "${service}: Running"
        else
            log_warning "${service}: Not running"
        fi
    done

    log_info "============================================"
}

# Stop the main IIIF stack (does not touch maintenance compose).
stop_services() {
    log_info "Stopping all services..."
    $DOCKER_COMPOSE_CMD down 2>/dev/null || true
    log_success "Services stopped"
}

# Tail the live logs of every service.
show_logs() {
    log_info "Showing service logs (Ctrl+C to exit)..."
    $DOCKER_COMPOSE_CMD logs -f
}

# Stop services and delete the entire output directory (interactive confirm).
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

# Swap the live stack out for the static maintenance page.
enable_maintenance() {
    log_warning "Enabling maintenance mode..."
    log_info "This will stop all services and show a maintenance page"

    stop_services

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
