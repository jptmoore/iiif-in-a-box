# IIIF-In-A-Box

A complete IIIF (International Image Interoperability Framework) service stack that transforms your images and annotations into a fully functional IIIF presentation with viewer, search, and annotation capabilities.

## How It Works

IIIF-In-A-Box creates **IIIF Collections** where each project represents a collection and individual annotation files become manifests within that collection. The system is **configuration-driven** using YAML for project metadata.

**Input:**
1. **📷 Images** (TIFF, JPEG, etc.) 
2. **📝 Annotations** (JSON files - each becomes a IIIF Manifest)
3. **⚙️ YAML Configuration** (project metadata, provider info, defaults)

**Output:**
- **📁 IIIF Collections** (projects as collections, annotation files as manifests)
- **🖼️ IIIF Image API** (via Cantaloupe image server)
- **👁️ Web Viewer** (Tamerlane IIIF viewer)
- **🔍 Collection-level Search** (via AnnoSearch with IIIF Content Search API)

## Quick Start

### 1. Configure Your Project
Edit `config/projects.yml` to define your project:
```yaml
projects:
  my-project:
    title: "My IIIF Collection" 
    description: "Description for the viewer"
    metadata:
      - label:
          en: ["Creator"]
        value:
          none: ["Your Name"]
```

### 2. Add Your Content
```bash
# Place your images  
cp your-images/* web/images/

# Place your annotations (each JSON file becomes a IIIF Manifest)
cp annotations1.json web/annotations/
cp annotations2.json web/annotations/
```

### 3. Build and Run
```bash
# Build complete IIIF service (fast - reuses existing Docker images)
./bootstrap.sh build my-project

# Force complete rebuild (slow - rebuilds everything including Cantaloupe)
./bootstrap.sh build my-project --force

# Or for demo with sample content
./bootstrap.sh build
```

### 4. Access Your IIIF Collection
- **📚 Main site**: http://localhost:8080
- **👁️ Viewer**: http://localhost:8080/viewer/ 
- **📁 Collection**: http://localhost:8080/iiif/my-project-collection.json
- **🔍 Search**: http://localhost:8080/annosearch/my-project/search?q=search-term
- **📝 Annotations**: http://localhost:8080/miiify/
- **🖼️ Images**: http://localhost:8080/cantaloupe/

## Content Structure

```
iiif-in-a-box/
├── config/
│   └── projects.yml      ← Configure projects here (YAML)
├── web/
│   ├── images/           ← Put your images here
│   ├── annotations/      ← Put annotation files here (each becomes a manifest)
│   ├── iiif/            ← Generated manifests + collections (auto-created)
│   └── pages/           ← Generated HTML pages (auto-created)
├── bootstrap.sh         ← Main build script
└── ...
```

## IIIF Collections Architecture

This system implements proper IIIF Collections:

- **📁 Project = IIIF Collection** (defined in `config/projects.yml`)
- **📄 Annotation File = IIIF Manifest** (each JSON file in `web/annotations/`)
- **🔍 Collection-level Search** (searches across all manifests in the collection)

### Generated Structure
```
web/iiif/
├── my-project-collection.json    ← IIIF Collection (contains all manifests)
├── my-project-manifest-1.json    ← IIIF Manifest (from annotations1.json) 
├── my-project-manifest-2.json    ← IIIF Manifest (from annotations2.json)
└── ...
```

## Build Process

The system uses a **configuration-driven build** optimized for IIIF Collections:

### Phase 1: Process Annotations into Manifests
- Reads project configuration from `config/projects.yml`
- Starts annotation processing infrastructure (miiify, annosearch, quickwit)
- Processes each annotation JSON file into a separate IIIF Manifest
- Creates a IIIF Collection containing all manifests for the project
- Indexes the collection for full-text search

### Phase 2: Build Complete Service  
- Builds all services with processed content using project-specific Docker images:
  - **Images** → served via Cantaloupe image server
  - **Generated collection + manifests** → served as static files
  - **Tamerlane viewer** → React-based IIIF viewer
  - **Search index** → IIIF Content Search API for the collection

### Docker Image Naming
Each project gets its own set of Docker images:
- `my-project-web` (instead of `proxy-web`)
- `my-project-miiify` (instead of `proxy-miiify`)
- `my-project-annosearch` (instead of `proxy-annosearch`)

### Result
A complete IIIF Collection service where:
- Each annotation file becomes a distinct IIIF Manifest
- All manifests are grouped in a project Collection
- Images are served via IIIF Image API
- Viewer displays the entire collection with navigation between manifests
- Search finds content across the entire collection via IIIF Content Search API
## Commands

```bash
# Build with your content (fast build using cached images)
./bootstrap.sh build my-project

# Force complete rebuild (slow - rebuilds everything)
./bootstrap.sh build my-project --force

# Build demo with sample content  
./bootstrap.sh build

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

## Examples

### Configure a Medieval Manuscript Collection
```yaml
# config/projects.yml
projects:
  medieval-manuscripts:
    title: "Medieval Manuscript Collection"
    description: "Digitized medieval manuscripts from the 12th century"
    metadata:
      - label:
          en: ["Period"]
        value:
          none: ["Medieval 1100-1200"]
      - label:
          en: ["Type"]
        value:
          en: ["Illuminated manuscripts"]
```

### Basic Image Collection
```bash
# 1. Add images
cp medieval-manuscripts/*.tif web/images/

# 2. Add annotation files (each becomes a manifest)
cp manuscript1-annotations.json web/annotations/
cp manuscript2-annotations.json web/annotations/

# 3. Build IIIF collection
./bootstrap.sh build medieval-manuscripts

# 4. View collection at http://localhost:8080/viewer/
# 5. Collection JSON at http://localhost:8080/iiif/medieval-manuscripts-collection.json
```

### Collection with Search
```bash
# 1. Add images and multiple annotation files
cp documents/*.jpg web/images/
cp document1-transcription.json web/annotations/
cp document2-transcription.json web/annotations/
cp document3-transcription.json web/annotations/

# 2. Configure project in projects.yml
# 3. Build with annotation processing
./bootstrap.sh build documents

# 4. View collection with multiple manifests
# 5. Search across entire collection at http://localhost:8080/annosearch/documents/search?q=your-search-term
```

## Architecture

The system consists of multiple containerized services:

- **🌐 nginx** (Port 8080) - Reverse proxy and routing
- **📄 Apache** - Serves static content and Tamerlane viewer at `/viewer/`
- **🖼️ Cantaloupe** - IIIF Image API server at `/cantaloupe/`
- **🔍 AnnoSearch** - Full-text search with Quickwit backend at `/annosearch/`
- **📝 Miiify** - IIIF annotation server at `/miiify/`
- **📊 Quickwit** - Search index backend

### Service Flow
```
YAML Configuration + Images + Annotation Files
        ↓
   [Processing Phase]
        ↓
Each Annotation File → Individual IIIF Manifest
All Manifests → Grouped into IIIF Collection
Images → Cantaloupe (IIIF Image API)
Collection → AnnoSearch (Collection-level Search)
        ↓
   [Web Service Phase]  
        ↓
nginx → Apache (viewer + collection + manifests) + Search + Images
```

## Content Types Supported

### Images
- **TIFF** (recommended for archival)
- **JPEG** (web-optimized)
- **PNG** (with transparency)
- **GIF** (simple graphics)

### Annotations
- **JSON** files in Web Annotation format (each file becomes a IIIF Manifest)
- **Transcriptions** (text overlay)
- **Tags and metadata**
- **Geometric annotations** (rectangles, polygons)

## Configuration System

### YAML Configuration (`config/projects.yml`)
```yaml
# Default settings for all projects
defaults:
  images_dir: "web/images"
  annotations_dir: "web/annotations"
  base_url: "http://localhost:8080"
  
  # Default provider information
  provider:
    id: "https://your-institution.org"
    type: "Agent"
    label:
      en: ["Your Institution Name"]

# Project-specific configurations  
projects:
  my-project:
    title: "Project Title"
    description: "Description for the viewer"
    metadata:
      - label:
          en: ["Creator"]
        value:
          none: ["Creator Name"]
      - label:
          en: ["Date"]
        value:
          none: ["2024"]
```

## Generated Output

When you build, the system generates:

- **� IIIF Collection** (`web/iiif/project-collection.json`) - Contains all manifests for the project
- **�📋 IIIF Manifests** (`web/iiif/project-manifest-*.json`) - One per annotation file
- **📄 HTML Pages** (`web/pages/*.html`) - Project-specific viewer pages  
- **🔍 Search Index** - Full-text searchable collection content
- **🌐 Complete Web Service** - Ready-to-use IIIF presentation
- **🐳 Project Docker Images** - Named with project prefix (e.g., `my-project-web`)

## Requirements

- **git** - For repository management
- **docker** - Container runtime
- **docker-compose** - Multi-container orchestration

## Directory Structure

```
iiif-in-a-box/           # Main project (this repository)
├── bootstrap.sh         # Main build script
├── config/             # Configuration
│   └── projects.yml    # ← Project definitions and metadata
├── web/                # Your content goes here
│   ├── images/         # ← Your images
│   ├── annotations/    # ← Your annotation files (each becomes a manifest)
│   ├── iiif/          # ← Generated collections and manifests
│   └── pages/         # ← Generated HTML pages
├── proxy/             # nginx + docker-compose configs
├── cantaloupe/        # Image server config
├── miiify/            # Annotation processing
└── ...

../                    # Parent directory (auto-managed)
├── tamerlane/         # IIIF Viewer (auto-cloned)
├── miiify/            # IIIF Tools (auto-cloned)  
└── annosearch/        # IIIF Search (auto-cloned)
```

## Security Features

- **HTTP method restrictions** - Annotation server allows only GET/HEAD
- **Non-root containers** - All services run as unprivileged users
- **Health checks** - Service monitoring and restart capability
- **CORS configuration** - Proper cross-origin setup for IIIF compliance
- **Local binding** - Services bound to localhost for security

## Troubleshooting

### Services won't start
```bash
./bootstrap.sh logs
```

### Check specific service
```bash
cd proxy
docker-compose -p my-project logs [service-name]
# Example: docker-compose -p my-project logs miiify
```

### Rebuild everything
```bash
./bootstrap.sh stop
./bootstrap.sh build my-project
```

### Check service health
```bash
./bootstrap.sh status
```

### Clear everything and start over
```bash
./bootstrap.sh stop
cd proxy && docker-compose -p my-project down -v  # Remove volumes
cd .. && ./bootstrap.sh build my-project
```

## Performance Tips

- **Fast builds**: Default build reuses existing Docker images (especially Cantaloupe which is slow to build)
- **Force rebuild**: Use `--force` flag only when you need to rebuild everything from scratch
- **TIFF images**: Use tiled TIFFs for better performance
- **Large collections**: Consider image pyramids for zoom performance  
- **Annotation files**: Organize related content into separate JSON files for better manifest structure
- **Collection search**: Larger collections will have better search results across all manifests
- **Project isolation**: Each project gets its own Docker images for clean separation

### Build Performance
- **First build**: ~5-10 minutes (downloads Cantaloupe JAR, builds all images)
- **Subsequent builds**: ~1-2 minutes (reuses cached Docker layers and images)
- **Force rebuild**: ~5-10 minutes (rebuilds everything from scratch)
- **Project switching**: Very fast (reuses existing images, only rebuilds content changes)
