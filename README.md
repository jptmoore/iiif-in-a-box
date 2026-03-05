# IIIF-In-A-Box v2

Transform images and annotations into a complete IIIF service with viewer, search, and annotation capabilities.

## Quick Start

```bash
# 1. Create Docker network (one-time setup)
docker network create iiif-network

# 2. Create a minimal test project
mkdir -p /tmp/my-iiif-project
cat > /tmp/my-iiif-project/config.yml << 'EOF'
project:
  name: demo
  title: "My First IIIF Collection"
  description: "Testing IIIF-in-a-Box"
EOF

# 3. Build and start services
./bootstrap.sh build --input-dir /tmp/my-iiif-project

# 4. Open in browser
# http://localhost:8080/pages/demo.html
# You should see a IIIF viewer (empty because we didn't add images yet)
```

### Next Steps

Add your own images and annotations:
```bash
# Copy your images
mkdir -p /tmp/my-iiif-project/images
cp /path/to/your/*.jpg /tmp/my-iiif-project/images/

# Rebuild
./bootstrap.sh build --input-dir /tmp/my-iiif-project
```

## What You Get

- **IIIF Image Server** - Zoomable images (IIPImage)
- **Annotation Server** - W3C Web Annotations (Miiify v2)
- **Full-text Search** - Search annotations (AnnoSearch + Quickwit)
- **Viewer Pages** - Auto-generated HTML viewers
- **IIIF Manifests** - IIIF Presentation API 3.0

## Input Directory Structure

```
my-project/
├── config.yml          # Project configuration (required)
├── images/             # Your images (optional)
│   ├── image1.tif
│   └── image2.jpg
└── annotations/        # W3C annotations (optional)
    ├── canvas-1/
    │   └── annotation-1.json
    └── canvas-2/
        └── annotation-2.json
```

## Configuration

### Minimal config.yml

Only `project.name` is required:

```yaml
project:
  name: my-project
  title: "My IIIF Collection"
  description: "Explore my collection"
```

### Full config.yml with metadata

Add optional metadata and provider information:

```yaml
project:
  name: my-project
  title: "My IIIF Collection"
  description: "Explore my collection using the IIIF viewer"
  
  metadata:
    - label:
        en: ["Creator"]
      value:
        none: ["Your Name"]
    - label:
        en: ["Date"]
      value:
        none: ["2024"]
    - label:
        en: ["Subjects"]
      value:
        en: ["Topic 1", "Topic 2"]
    - label:
        en: ["Copyright"]
      value:
        en: ["© Your Institution"]

provider:
  id: "https://your-institution.org"
  type: "Agent"
  label:
    en:
      - "Your Institution"
      - "Address Line"
      - "City, ZIP"
      - "https://your-institution.org"
  homepage:
    - id: "https://your-institution.org"
      type: "Text"
      label:
        en: ["Visit our website"]
```

## Commands

```bash
# Build and start
./bootstrap.sh build --input-dir /path/to/input

# Specify output directory (default: ./output)
./bootstrap.sh build --input-dir /path/to/input --output-dir /custom/output

# Deploy with custom hostname
./bootstrap.sh build --input-dir /path/to/input --hostname https://yourdomain.com

# Manage services
./bootstrap.sh status        # View service status
./bootstrap.sh stop          # Stop all services
./bootstrap.sh restart       # Restart services
./bootstrap.sh logs          # View logs
./bootstrap.sh maintenance   # Enable maintenance mode
```

## Services (all on port 8080)

- **Viewer** - `http://localhost:8080/pages/{project}.html`
- **Manifests** - `http://localhost:8080/iiif/{project}.json`
- **Images** - `http://localhost:8080/iiif/` (IIIF Image API)
- **Annotations** - `http://localhost:8080/miiify/`
- **Search** - `http://localhost:8080/annosearch/{project}/search`

## Output Directory

Generated files go to `./output/` (or your specified directory):

```
output/
├── miiify/
│   ├── git_store/      # Miiify internal storage
│   └── pack_store/     # Annotation packs
├── web/                # Static web content (served by nginx)
│   ├── iiif/          # Generated IIIF manifests
│   ├── pages/         # Generated viewer pages
│   └── images/        # Processed images
├── annosearch/
│   └── qwdata/        # Quickwit search index data
└── logs/              # Service logs
```

## Requirements

- Docker & Docker Compose v2
- Git

**First-time setup:**
```bash
# Create the shared Docker network (only needed once)
docker network create iiif-network
```

The bootstrap script automatically:
- Pulls all required Docker images
- Generates manifests and viewer pages
- Starts all services
- Indexes annotations for search

## Troubleshooting

**Services won't start:**
```bash
./bootstrap.sh stop
./bootstrap.sh build --input-dir /path/to/input
```

**Lock errors:**
- Script automatically stops services before building
- Use `./bootstrap.sh stop` to manually stop

**Search not working:**
- Wait ~10 seconds after services start for indexing
- Check manifest exists: `ls output/web/iiif/`

## Architecture

Pre-built Docker images:
- **nginx** - Reverse proxy & static files
- **IIPImage** (`iipsrv/iipsrv:latest`) - IIIF Image API 2.0/3.0
- **Miiify** (`ghcr.io/nationalarchives/miiify:latest`) - W3C Web Annotation server
- **AnnoSearch** (`ghcr.io/nationalarchives/annosearch:latest`) - IIIF Content Search API
- **Quickwit** (`quickwit/quickwit`) - Full-text search engine

All services on Docker network `iiif-network`.
