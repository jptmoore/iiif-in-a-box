# IIIF-In-A-Box

A complete IIIF (International Image Interoperability Framework) service stack that transforms your images and annotations into a fully functional IIIF presentation with viewer, search, and annotation capabilities.

## How It Works

IIIF-In-A-Box is **data-driven** - you provide two key inputs:
1. **📷 Images** (TIFF, JPEG, etc.) 
2. **📝 Annotations** (JSON files, required for manifest generation)

The system processes these to create:
- **🖼️ IIIF Image API** (via Cantaloupe image server)
- **📋 IIIF Manifests** (generated from your annotations)
- **👁️ Web Viewer** (Tamerlane IIIF viewer)
- **🔍 Search** (full-text search across annotations)

## Quick Start

### 1. Add Your Content
```bash
# Place your images
cp your-images/* web/images/

# Place your annotations (required for manifests)
cp your-annotations.json web/annotations/
```

### 2. Build and Run
```bash
# Build complete IIIF service (fast - reuses existing Docker images)
./bootstrap.sh build my-project

# Force complete rebuild (slow - rebuilds everything including Cantaloupe)
./bootstrap.sh build my-project --force

# Or for demo with sample content
./bootstrap.sh build
```

### 3. Access Your IIIF Service
- **📚 Main site**: http://localhost:8080
- **👁️ Viewer**: http://localhost:8080/viewer/
- **🔍 Search**: http://localhost:8080/annosearch/
- **📝 Annotations**: http://localhost:8080/miiify/
- **🖼️ Images**: http://localhost:8080/cantaloupe/

## Content Structure

```
iiif-in-a-box/
├── web/
│   ├── images/           ← Put your images here
│   ├── annotations/      ← Put your annotation files here (required)
│   ├── iiif/            ← Generated manifests (auto-created)
│   └── pages/           ← Generated HTML pages (auto-created)
├── bootstrap.sh         ← Main build script
└── ...
```

## Build Process

The system uses a **two-phase build** optimized for your content:

### Phase 1: Process Annotations
- Starts annotation processing infrastructure (miiify)
- Loads your annotations into the annotation server
- Generates IIIF manifests that reference both images and annotations

### Phase 2: Build Complete Service  
- Builds all services with processed content:
  - **Images** → served via Cantaloupe image server
  - **Generated manifests** → served as static files
  - **Tamerlane viewer** → React-based IIIF viewer
  - **Search index** → full-text search across annotations

### Result
A complete IIIF service where:
- Images are served via IIIF Image API
- Manifests link images to annotations  
- Viewer displays images with overlay annotations
- Search finds content across all annotations
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

### Basic Image Collection
```bash
# 1. Add images
cp medieval-manuscripts/*.tif web/images/

# 2. Build IIIF service
./bootstrap.sh build medieval-manuscripts

# 3. View at http://localhost:8080/viewer/
```

### Images + Annotations
```bash
# 1. Add images and annotations
cp documents/*.jpg web/images/
cp transcriptions.json web/annotations/

# 2. Build with annotation processing
./bootstrap.sh build documents

# 3. View images with overlay annotations
# 4. Search transcriptions at http://localhost:8080/annosearch/
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
Your Images + Annotations
        ↓
   [Processing Phase]
        ↓
Images → Cantaloupe (IIIF Image API)
Annotations → Miiify (Annotation API) + Manifests
        ↓
   [Web Service Phase]  
        ↓
nginx → Apache (viewer + manifests) + Search + Images
```

## Content Types Supported

### Images
- **TIFF** (recommended for archival)
- **JPEG** (web-optimized)
- **PNG** (with transparency)
- **GIF** (simple graphics)

### Annotations
- **JSON** files in Web Annotation format
- **Transcriptions** (text overlay)
- **Tags and metadata**
- **Geometric annotations** (rectangles, polygons)

## Generated Output

When you build, the system generates:

- **📋 IIIF Manifests** (`web/iiif/*.json`) - Link images to annotations
- **📄 HTML Pages** (`web/pages/*.html`) - Project-specific viewer pages  
- **🔍 Search Index** - Full-text searchable annotation content
- **🌐 Complete Web Service** - Ready-to-use IIIF presentation

## Requirements

- **git** - For repository management
- **docker** - Container runtime
- **docker-compose** - Multi-container orchestration

## Directory Structure

```
iiif-in-a-box/           # Main project (this repository)
├── bootstrap.sh         # Main build script
├── web/                # Your content goes here
│   ├── images/         # ← Your images
│   ├── annotations/    # ← Your annotation files
│   ├── iiif/          # ← Generated manifests
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
docker-compose logs [service-name]
# Example: docker-compose logs miiify
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
cd proxy && docker-compose down -v  # Remove volumes
cd .. && ./bootstrap.sh build my-project
```

## Performance Tips

- **Fast builds**: Default build reuses existing Docker images (especially Cantaloupe which is slow to build)
- **Force rebuild**: Use `--force` flag only when you need to rebuild everything from scratch
- **TIFF images**: Use tiled TIFFs for better performance
- **Large collections**: Consider image pyramids for zoom performance  
- **Annotations**: Group related annotations in single JSON files
- **Search**: Larger annotation collections will have better search results

### Build Performance
- **First build**: ~5-10 minutes (downloads Cantaloupe JAR, builds all images)
- **Subsequent builds**: ~1-2 minutes (reuses cached Docker layers and images)
- **Force rebuild**: ~5-10 minutes (rebuilds everything from scratch)
