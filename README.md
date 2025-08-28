# IIIF-In-A-Box Bootstrap

This bootstrap script automates the setup of your complete IIIF-In-A-Box environment.

## What it does

The bootstrap script automatically:

1. **Checks dependencies** (git, docker, docker-compose)
2. **Clones/updates repositories** for:
   - tamerlane (IIIF Viewer)
   - miiify (IIIF annotation server)
   - annosearch (IIIF cotent search server)
3. **Builds and starts** all Docker services
4. **Provides management commands** for the running services

## Quick Start

```bash
# From the dd project root
./bootstrap.sh
```

After successful startup, your IIIF-In-A-Box will be available at:
- **Main site**: http://localhost:8080
- **Tamerlane viewer**: http://localhost:8080/viewer/
- **Search service**: http://localhost:8080/annosearch/
- **Annotation service**: http://localhost:8080/miiify/
- **Image service**: http://localhost:8080/cantaloupe/ (Cantaloupe)

## Commands

```bash
# Full setup (default)
./bootstrap.sh

# Only update repositories (no build)
./bootstrap.sh update-only

# Show service status
./bootstrap.sh status

# Stop all services
./bootstrap.sh stop

# Restart services
./bootstrap.sh restart

# View service logs
./bootstrap.sh logs
```

## Requirements

- git
- docker
- docker-compose (or docker compose)

## Directory Structure

After running the bootstrap, you'll have:

```
dd/                      # Main project (this directory)
├── bootstrap.sh         # Bootstrap script
├── web/                # Web service
├── proxy/              # Nginx proxy + docker-compose
├── cantaloupe/         # Image server
└── ...

../                     # Parent directory
├── tamerlane/          # IIIF Viewer (cloned)
├── miiify/             # IIIF Tools (cloned)  
└── annosearch/         # IIIF Search (cloned)
```

## Architecture

- **nginx** (Port 8080) - Reverse proxy and routing
- **Apache** - Serves web content and Tamerlane viewer at `/viewer/`
- **Cantaloupe** - IIIF Image API server at `/cantaloupe/`
- **AnnoSearch** - IIIF search with Quickwit backend at `/annosearch/`
- **Miiify** - IIIF annotations `/miiify/` (GET/HEAD only)

## Security Features

- HTTP method restrictions on miiify (only GET/HEAD allowed)
- Non-root user execution in containers
- Health checks for service monitoring
- CORS configuration for IIIF compliance

## Troubleshooting

**Services won't start:**
```bash
./bootstrap.sh logs
```

**Check individual service:**
```bash
cd proxy
docker-compose logs [service-name]
```

**Rebuild everything:**
```bash
./bootstrap.sh stop
./bootstrap.sh
```

**Check service health:**
```bash
./bootstrap.sh status
```
