# IIIF-In-A-Box v2

**The simplest way to publish IIIF content.**

Transform images and annotations into a complete IIIF service with viewer, search, and annotation capabilities - in minutes, not days.

## Why IIIF-in-a-Box?

✅ **One Dependency** - Just Docker. No language runtimes, no build chains, no complexity.  
✅ **Simple File Structure** - Flat directories with dash-separated names. No nested folders to manage.  
✅ **Automatic Organization** - System creates proper IIIF Collections and Manifests from your naming.  
✅ **Deploy Anywhere** - Works on any VM, cloud instance, or local machine with Docker.  
✅ **Complete Solution** - Image server, annotations, search, and viewer - all integrated.  
✅ **Shell Scripts Only** - Easy to understand, modify, and maintain. No magic frameworks.

## Perfect For

📚 **Digital Libraries** - Publish manuscript collections with transcriptions and annotations  
🎓 **Academic Research** - Share annotated image datasets with collaborators  
🏛️ **Archives & Museums** - Make collections accessible with minimal IT overhead  
📖 **Digital Humanities** - Focus on content, not infrastructure  
🔬 **Researchers** - Self-host your image collections with full IIIF compatibility  

If you have images and want to publish them with IIIF standards but don't want to become a DevOps expert - this is for you.

## Quick Start

**Go from zero to a working IIIF server in under 5 minutes.**

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
# (Tamerlane viewer will be pulled from ghcr.io automatically)
./bootstrap.sh build --input-dir /tmp/my-iiif-project

# 4. Open in browser
# http://localhost:8080/pages/demo.html
# Done! Your IIIF viewer is running.
```

### Add Your Content

**No nested directories. No complex paths. Just simple, flat file naming.**

```bash
# Copy your images (use dashes to organize)
mkdir -p /tmp/my-iiif-project/images
cp chapter1-page01.jpg /tmp/my-iiif-project/images/
cp chapter1-page02.jpg /tmp/my-iiif-project/images/
cp chapter2-page01.jpg /tmp/my-iiif-project/images/

# Rebuild
./bootstrap.sh build --input-dir /tmp/my-iiif-project

# System automatically creates:
# - Collection with nested structure
# - IIIF Manifests for each chapter
# - Viewer pages
# - Search indexes
```

## What You Get

**A complete, production-ready IIIF publishing stack:**

- 🖼️ **IIIF Image Server** - Zoomable deep-zoom images (IIPImage)
- 📝 **Annotation Server** - W3C Web Annotations with version control (Miiify v2)
- 🔍 **Full-text Search** - Fast annotation search (AnnoSearch + Quickwit)
- 👀 **Modern Viewer** - Beautiful IIIF viewer with annotation support (Tamerlane)
- 📋 **IIIF Manifests** - Automatic Manifest/Collection generation (IIIF Presentation API 3.0)
- 🚀 **One Command Deploy** - Everything configured and integrated

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

**Why This Approach is Better:**
- ✅ **All images in one folder** - No creating nested directory structures
- ✅ **Visual clarity** - See your entire collection at a glance
- ✅ **Easy bulk operations** - Rename, sort, filter files with standard tools
- ✅ **Annotation folders match exactly** - Simple one-to-one naming (without extension)
- ✅ **System handles complexity** - Automatic reorganization into proper IIIF structure
- ✅ **Future-proof** - Dashes become slashes: `volume1-chapter1-page001.jpg` → `volume1/chapter1/page001.jpg`

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

**Minimal dependencies for maximum portability:**

- ✅ Docker & Docker Compose v2
- ✅ Git

**That's it.** No Python, Node.js, Ruby, or language-specific toolchains required.

Works on any platform: Linux servers, macOS, Windows, cloud VMs, Raspberry Pi, or your laptop.

**Apple Silicon Macs (M1/M2/M3):**
- IIPImage server runs using AMD64 emulation (configured automatically)
- Miiify and AnnoSearch: Use local ARM64 builds if available, otherwise pull AMD64 images
- To build ARM64 images locally:
  ```bash
  # Clone and build miiify
  git clone https://github.com/nationalarchives/miiify.git
  cd miiify && docker build -t ghcr.io/nationalarchives/miiify:latest .
  
  # Clone and build annosearch  
  git clone https://github.com/nationalarchives/annosearch.git
  cd annosearch && docker build -t ghcr.io/nationalarchives/annosearch:latest .
  ```

**Tamerlane Viewer:**
The bootstrap script automatically pulls Tamerlane from GitHub Container Registry (ghcr.io).

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
- Bootstrap script automatically pulls Tamerlane from ghcr.io
- Ensure the Tamerlane image is available for your architecture
- Run `./bootstrap.sh stop && ./bootstrap.sh build --input-dir /path/to/input` to rebuild

## Architecture

**Battle-tested open source components, thoughtfully integrated:**

Pre-built Docker images:
- **nginx** - Reverse proxy & static files
- **IIPImage** (`iipsrv/iipsrv:latest`) - Fast IIIF Image API 2.0/3.0 server [AMD64]
- **Miiify** (`ghcr.io/nationalarchives/miiify:latest`) - W3C Web Annotation server with Git storage
- **AnnoSearch** (`ghcr.io/nationalarchives/annosearch:latest`) - IIIF Content Search API implementation
- **Quickwit** (`quickwit/quickwit`) - High-performance search engine
- **Tamerlane** (`ghcr.io/tamerlaneviewer/tamerlane:latest`) - Modern IIIF viewer with rich annotation support

**Design Philosophy:**
- Shell scripts for transparency and hackability
- Docker for isolation and portability  
- Single network, single port (8080) for simplicity
- Convention over configuration (smart defaults)
- Fail fast with clear error messages

All services communicate on Docker network `iiif-network`.
