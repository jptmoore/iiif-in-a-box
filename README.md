# IIIF-In-A-Box v2

Transform images and annotations into a complete IIIF service with viewer, search, and annotation capabilities.

## Quick Start

```bash
# 1. Create Docker network (one-time setup)
docker network create iiif-network

# 2. Clone Tamerlane viewer (required)
git clone https://github.com/tamerlaneviewer/tamerlane.git

# 3. Create a minimal test project
mkdir -p /tmp/my-iiif-project
cat > /tmp/my-iiif-project/config.yml << 'EOF'
project:
  name: demo
  title: "My First IIIF Collection"
  description: "Testing IIIF-in-a-Box"
EOF

# 4. Build and start services
./bootstrap.sh build --input-dir /tmp/my-iiif-project

# 5. Open in browser
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

**Simple Project (Single Manifest):**
```
my-project/
├── config.yml          # Project configuration (required)
├── images/             # Your images (flat - no dashes in names)
│   ├── image1.tif
│   └── image2.jpg
└── annotations/        # Annotation folders (match image names exactly)
    ├── image1/
    │   └── annotation-1.json
    └── image2/
        └── annotation-2.json
```

**Collection Project (organized with dashes):**
```
my-book/
├── config.yml          # Project configuration (required)
├── images/             # Images with dash-separated names (flat directory)
│   ├── chapter1-page001.jpg
│   ├── chapter1-page002.jpg
│   ├── chapter2-page001.jpg
│   └── chapter2-page002.jpg
└── annotations/        # Annotation folders (match image names exactly)
    ├── chapter1-page001/
    │   └── annotation-1.json
    ├── chapter1-page002/
    │   └── annotation-1.json
    ├── chapter2-page001/
    │   └── annotation-1.json
    └── chapter2-page002/
        └── annotation-1.json
```

**Nested Collections (multi-level with dashes):**
```
domesday/
├── config.yml
├── images/             # All images flat with dash-separated names
│   ├── volume1-chapter1-page001.jpg
│   ├── volume1-chapter1-page002.jpg
│   ├── volume1-chapter2-page001.jpg
│   ├── volume1-chapter2-page002.jpg
│   ├── volume2-chapter1-page001.jpg
│   └── volume2-chapter1-page002.jpg
└── annotations/        # Annotation folders (match image names exactly)
    ├── volume1-chapter1-page001/
    │   └── annotation-1.json
    ├── volume1-chapter1-page002/
    │   └── annotation-1.json
    ├── volume1-chapter2-page001/
    │   └── annotation-1.json
    ├── volume1-chapter2-page002/
    │   └── annotation-1.json
    ├── volume2-chapter1-page001/
    │   └── annotation-1.json
    └── volume2-chapter1-page002/
        └── annotation-1.json
```

The system automatically detects:
- **No dashes** in image names → Generates single Manifest with multiple Canvases
- **One dash level** (e.g., `chapter1-page001`) → Generates Collection with Manifests (one per first segment)
- **Multiple dash levels** (e.g., `volume1-chapter1-page001`) → Generates nested Collections recursively

**Key Principles:**
- **All images remain flat** in the input `images/` directory
- **Use dashes** (`-`) in filenames to define hierarchy (e.g., `volume1-chapter1-page001.jpg`)
- **Annotation folders match image names exactly** (without extension)
- The system **reorganizes images into nested directories** in the output automatically
- Dashes become directory separators: `volume1-chapter1-page001.jpg` → `volume1/chapter1/page001.jpg`

**Annotation Targets:**
Annotations must target the correct Canvas ID based on the dash-separated structure:
- No dashes: `http://localhost:8080/iiif/canvas/photo`
- One level: `http://localhost:8080/iiif/canvas/chapter1/page001`
- Multiple levels: `http://localhost:8080/iiif/canvas/volume1/chapter1/page001`

**Important:** The build process validates that annotation folders match image filenames exactly and will fail if they don't match.

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

**Apple Silicon Macs (M1/M2/M3):**
- IIPImage server runs using AMD64 emulation (configured automatically)
- Miiify and AnnoSearch: Use local ARM64 builds if available, otherwise pull AMD64 images
- To build ARM64 images locally:
  ```bash
  # Clone and build miiify
  git clone https://github.com/nationalarchives/miiify.git
  cd miiify && docker build -t ghcr.io/nationalarchives/miiify:latest .
  
  # Clone and build annosearch  
  git clone https://github.com/annosearch/annosearch.git
  cd annosearch && docker build -t ghcr.io/annosearch/annosearch:latest .
  ```

**Tamerlane Viewer (Required):**
The viewer requires Tamerlane to be built locally (no published image yet):
```bash
# Clone Tamerlane into the iiif-in-a-box directory
git clone https://github.com/tamerlaneviewer/tamerlane.git

# Tamerlane will be built automatically by docker-compose
# when you run the bootstrap script
```

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

**ARM64 architecture error (Apple Silicon Macs):**
- IIPImage runs using AMD64 emulation (already configured)
- If you still see platform errors, ensure Docker Desktop is updated
- Performance may be slightly slower than native ARM64 images

**Viewer not loading:**
- Ensure Tamerlane is cloned: `git clone https://github.com/tamerlaneviewer/tamerlane.git`
- The `tamerlane` directory must be in the same directory as `docker-compose.yml`
- Run `./bootstrap.sh stop && ./bootstrap.sh build --input-dir /path/to/input` to rebuild

## Architecture

Pre-built Docker images:
- **nginx** - Reverse proxy & static files
- **IIPImage** (`iipsrv/iipsrv:latest`) - IIIF Image API 2.0/3.0 [AMD64 only]
- **Miiify** (`ghcr.io/nationalarchives/miiify:latest`) - W3C Web Annotation server [ARM64 via local build]
- **AnnoSearch** (`ghcr.io/annosearch/annosearch:latest`) - IIIF Content Search API [ARM64 via local build]
- **Quickwit** (`quickwit/quickwit`) - Full-text search engine
- **Tamerlane** (local build required) - IIIF Viewer with annotation support

All services on Docker network `iiif-network`.
