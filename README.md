# IIIF-In-A-Box v2

**The simplest way to publish IIIF content.**

Transform images and annotations into a complete IIIF service with viewer, search, and annotation capabilities - in minutes, not days.

## Why IIIF-in-a-Box?

✅ **One Dependency** - Just Docker. No language runtimes, no build chains, no complexity.  
✅ **Flexible Structure** - Use flat files with dashes OR nested directories - your choice.  
✅ **Automatic Organization** - System detects hierarchy and creates proper IIIF Collections/Manifests.  
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

**Use flat files with dash-separated names (recommended):**

```bash
# Simple manifest (flat files)
mkdir -p /tmp/my-iiif-project/images
mkdir -p /tmp/my-iiif-project/annotations/page01
mkdir -p /tmp/my-iiif-project/annotations/page02

cp image1.jpg /tmp/my-iiif-project/images/page01.jpg
cp image2.jpg /tmp/my-iiif-project/images/page02.jpg

# Collection + Manifest (dash-separated hierarchy)
cp image1.tif /tmp/my-iiif-project/images/book-chapter1-001.tif
cp image2.tif /tmp/my-iiif-project/images/book-chapter1-002.tif
mkdir -p /tmp/my-iiif-project/annotations/book-chapter1-001
mkdir -p /tmp/my-iiif-project/annotations/book-chapter1-002

# Rebuild
./bootstrap.sh build --input-dir /tmp/my-iiif-project

# System automatically:
# - Detects 'book-chapter1-' pattern
# - Creates Collection: book.json
# - Creates Manifest: chapter1.json
# - Generates viewer, search indexes, etc.
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

**The system supports two approaches for organizing your images:**

### Approach 1: Flat Files with Dash-Separated Names (Recommended)

Use dashes to encode hierarchy in flat filenames. This mirrors the Miiify annotation server's container structure.

**Simple Manifest (single level):**
```
my-project/
├── config.yml          # Project configuration (required)
├── images/             # Flat directory with simple names
│   ├── page01.jpg
│   └── page02.jpg
└── annotations/        # Annotation folders match image names
    ├── page01/
    │   └── annotation-1.json
    └── page02/
        └── annotation-2.json
```
→ Creates: **my-project.json** (Manifest with 2 canvases)

**Collection with Manifest (two levels):**
```
domesday/
├── config.yml
├── images/             # Dash-separated: collection-manifest-canvas
│   ├── domesday-lincolnshire-0680.tif
│   ├── domesday-lincolnshire-0714.tif
│   └── domesday-lincolnshire-0740.tif
└── annotations/        # Folders match image names exactly
    ├── domesday-lincolnshire-0680/
    │   ├── anno-001.json
    │   └── anno-002.json
    ├── domesday-lincolnshire-0714/
    │   └── anno-001.json
    └── domesday-lincolnshire-0740/
        └── anno-001.json
```
→ Creates:
- **domesday.json** (Collection) 
- **lincolnshire.json** (Manifest with 3 canvases)

**Naming pattern:** `{collection}-{manifest}-{canvas}.{ext}`  
**System parses dashes** to detect: collection=domesday, manifest=lincolnshire, canvas=0680

**Nested Collections (arbitrary depth):**
```
archive/
├── config.yml
├── images/             # Dash-separated: collection-subcollection-manifest-canvas
│   ├── archive-volume1-chapter1-page01.tif
│   ├── archive-volume1-chapter1-page02.tif
│   ├── archive-volume1-chapter2-page01.tif
│   ├── archive-volume2-chapter1-page01.tif
│   └── archive-volume2-chapter1-page02.tif
└── annotations/        # Folders match image names exactly
    ├── archive-volume1-chapter1-page01/
    │   └── anno-001.json
    ├── archive-volume1-chapter1-page02/
    │   └── anno-001.json
    ├── archive-volume1-chapter2-page01/
    │   └── anno-001.json
    ├── archive-volume2-chapter1-page01/
    │   └── anno-001.json
    └── archive-volume2-chapter1-page02/
        └── anno-001.json
```
→ Creates:
- **archive.json** (Collection) → volume1.json, volume2.json
- **volume1.json** (Collection) → chapter1.json, chapter2.json
- **volume2.json** (Collection) → chapter1.json
- **chapter1.json**, **chapter2.json** (Manifests with canvases)

**Pattern for arbitrary depth:** `{level1}-{level2}-{level3}-...-{canvas}.{ext}`  
**System automatically detects** nesting depth and creates appropriate Collections/Manifests

### Approach 2: Directory-Based Hierarchy

Use actual directories to organize images. System preserves structure as-is.

**Collection with subdirectories:**
```
my-book/
├── config.yml
├── images/
│   ├── chapter1/
│   │   ├── page01.jpg
│   │   └── page02.jpg
│   └── chapter2/
│       ├── page01.jpg
│       └── page02.jpg
└── annotations/
    ├── chapter1-page01/       # Note: flattened with dashes
    │   └── annotation-1.json
    ├── chapter1-page02/
    │   └── annotation-1.json
    ├── chapter2-page01/
    │   └── annotation-1.json
    └── chapter2-page02/
        └── annotation-1.json
```
→ Creates Collection with 2 Manifests (chapter1.json, chapter2.json)

**Nested structure:**
```
archive/
├── config.yml
├── images/
│   ├── volume1/
│   │   ├── chapter1/
│   │   │   ├── page01.jpg
│   │   │   └── page02.jpg
│   │   └── chapter2/
│   │       └── page01.jpg
│   └── volume2/
│       └── chapter1/
│           └── page01.jpg
└── annotations/
    ├── volume1-chapter1-page01/   # Flattened: slashes → dashes
    │   └── annotation-1.json
    ├── volume1-chapter1-page02/
    │   └── annotation-1.json
    ├── volume1-chapter2-page01/
    │   └── annotation-1.json
    └── volume2-chapter1-page01/
        └── annotation-1.json
```
→ Creates nested Collections and Manifests

## How It Works: Images → IIIF Hierarchy

### Structure Detection

The system analyzes your image filenames/folders to automatically create the correct IIIF structure:

**Flat files (no dashes):** Single Manifest  
**Flat files with dashes:** Detects hierarchy from dash patterns  
**Subdirectories:** Collection with Manifests per directory  

### Dash-Separated Naming (Flat Files)

**Pattern (2 levels):** `{collection}-{manifest}-{canvas}.{ext}`

Example: `domesday-lincolnshire-0680.tif`
- Collection: `domesday`
- Manifest: `lincolnshire`  
- Canvas: `0680`

**Pattern (arbitrary depth):** `{level1}-{level2}-{level3}-...-{canvas}.{ext}`

Example: `archive-volume1-chapter1-page01.tif`
- Collection: `archive` → Sub-collection: `volume1` → Manifest: `chapter1` → Canvas: `page01`

**How detection works:**
1. System scans all image files
2. Detects common dash-separated prefixes
3. Builds hierarchy tree (arbitrarily deep)
4. Generates nested Collections + Manifests automatically
5. Last level before canvas ID = Manifest, all others = Collections

### Directory-Based Naming

**Pattern:** `{collection}/{manifest}/{canvas}.{ext}`

Example: `images/domesday/lincolnshire/0680.tif`
- Collection: `domesday`
- Manifest: `lincolnshire`
- Canvas: `0680`

**How detection works:**
1. System walks directory tree
2. Each subdirectory = hierarchy level
3. Generates nested Collections/Manifests

### Annotation Folder Naming

**Critical:** Annotation folders must use **flattened** format (always with dashes), regardless of which image approach you use.

**Flat files:**
```
images/domesday-lincolnshire-0680.tif  →  annotations/domesday-lincolnshire-0680/
```

**Directories:**
```
images/domesday/lincolnshire/0680.tif  →  annotations/domesday-lincolnshire-0680/
```

**Why?** The Miiify annotation server uses Git for version control, which requires flat container names (no slashes in branch names).

### Canvas IDs (IIIF URLs)

Canvas IDs **always** use slashes (hierarchical paths):

```
Flat file: domesday-lincolnshire-0680.tif
→ Canvas ID: /iiif/canvas/domesday/lincolnshire/0680

Directory: domesday/lincolnshire/0680.tif  
→ Canvas ID: /iiif/canvas/domesday/lincolnshire/0680
```

**Result:** Same Canvas ID regardless of source structure!

### Annotation URLs

Individual annotations use the **flattened** container name:

```
Container: domesday-lincolnshire-0680
Annotation: anno-001
URL: http://localhost:8080/miiify/domesday-lincolnshire-0680/anno-001
```

**Example annotation JSON:**
```json
{
  "id": "http://localhost:8080/miiify/domesday-lincolnshire-0680/anno-001",
  "type": "Annotation",
  "target": "http://localhost:8080/iiif/canvas/domesday/lincolnshire/0680#xywh=172,412,1236,456"
}
```

**Key difference:**  
- `id`: Uses container format (dashes) → `/miiify/domesday-lincolnshire-0680/anno-001`
- `target`: Uses canvas ID (slashes) → `/iiif/canvas/domesday/lincolnshire/0680`

### Generated Manifest Files

**Flat files (no pattern):**
```
images/page01.jpg → {project-name}.json
```
Uses `project.name` from config.yml

**Flat files with dash pattern:**
```
images/domesday-lincolnshire-0680.tif
→ domesday.json (Collection)
→ lincolnshire.json (Manifest)
```

**Directories:**
```
images/chapter1/page01.jpg
→ {project-name}.json (Collection)
→ chapter1.json (Manifest)
```

### Validation

The build process validates:
- ✅ Annotation folders match image naming (flattened)
- ✅ Canvas IDs are correctly formatted
- ✅ Annotation targets reference valid canvases
- ✅ Collection/Manifest structure is valid IIIF

**Build fails if:**
- ❌ Annotation folder doesn't match image name
- ❌ Annotation target references non-existent canvas
- ❌ Mixed naming patterns in same project

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
│   └── pack_store/     # Annotation packs (mounted into miiify container)
├── web/                # Static web content (mounted into nginx container)
│   ├── iiif/          # Generated IIIF manifests
│   ├── pages/         # Generated viewer pages
│   └── images/        # Processed images (mounted into iipimage container)
├── annosearch/
│   └── qwdata/        # Quickwit search index data (mounted into quickwit container)
└── logs/              # Service logs
```

**Important:** The output directory is **mounted as Docker volumes** into containers, not baked into images. This means:
- ✅ Content persists outside containers and survives rebuilds
- ✅ You can update content without recreating containers
- ✅ Easy to backup, version control, or move to another server
- ✅ Switching projects automatically cleans the output directory to prevent mixed content

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
- **Volume mounts for content** - Generated content lives in `./output/` and is mounted into containers, not baked into images
- Single network, single port (8080) for simplicity
- Convention over configuration (smart defaults)
- Fail fast with clear error messages

All services communicate on Docker network `iiif-network`.
