# IIIF-In-A-Box

A complete IIIF (International Image Interoperability Framework) service stack that tra## Generated Output

- **📁 IIIF Collection** (`project-collection.json`) - Contains all manifests
- **📋 IIIF Manifests** (`project-manifest-*.json`) - One per annotation file
- **📄 HTML Pages** - Project-specific viewer pages  
- **🔍 Search Index** - Full-text searchable collection
- **🐳 Project Docker Images** - Named with project prefix

## Requirements & Setup

- **git, docker, docker-compose**
- Clone repositories are auto-managed in parent directory
- First build: ~5-10 minutes, subsequent: ~1-2 minutesges and annotations into IIIF Collections with viewer, search, and annotation capabilities.

## How It Works

Creates **IIIF Collections** where each project represents a collection and individual annotation files become manifests within that collection.

**Input:**
- **📷 Images** (TIFF, JPEG, etc.) 
- **📝 Annotations** (JSON files - each becomes a IIIF Manifest)
- **⚙️ YAML Configuration** (project metadata in `config/projects.yml`)

**Output:**
- **📁 IIIF Collections** (projects as collections, annotation files as manifests)
- **🖼️ IIIF Image API** via Cantaloupe
- **👁️ Web Viewer** via Tamerlane
- **🔍 Collection-level Search** via AnnoSearch

## Quick Start

```bash
# 1. Configure your project in config/projects.yml
# 2. Add images to web/images/
# 3. Add annotation files to web/annotations/ (each becomes a manifest)
# 4. Build and run
./bootstrap.sh build my-project

# Access your IIIF Collection at http://localhost:8080
```

### Configuration Example
Edit `config/projects.yml`:
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

## Architecture

IIIF Collections where:
- **📁 Project = IIIF Collection** (defined in `config/projects.yml`)
- **📄 Annotation File = IIIF Manifest** (each JSON file in `web/annotations/`)
- **🔍 Collection-level Search** (searches across all manifests)
- **🐳 Project-specific Docker images** (e.g., `my-project-web` instead of `proxy-web`)

### Services
- **🌐 nginx** (8080) - Reverse proxy
- **📄 Apache** - Viewer and static content at `/viewer/`
- **🖼️ Cantaloupe** - IIIF Image API at `/cantaloupe/`
- **🔍 AnnoSearch** - Full-text search at `/annosearch/`
- **📝 Miiify** - Annotation server at `/miiify/`
- **📊 Quickwit** - Search backend

### Content Structure
```
config/projects.yml      ← Project configuration
web/images/             ← Your images
web/annotations/        ← Annotation files (each → manifest)
web/iiif/              ← Generated collections + manifests
web/pages/             ← Generated HTML pages
```
## Commands

```bash
./bootstrap.sh build my-project        # Build with your content
./bootstrap.sh build my-project --force # Force complete rebuild
./bootstrap.sh build                   # Demo with sample content
./bootstrap.sh status                  # Show service status  
./bootstrap.sh stop                    # Stop services
./bootstrap.sh restart                 # Restart services
./bootstrap.sh logs                    # View logs
```

## Configuration

YAML configuration in `config/projects.yml`:

```yaml
defaults:
  base_url: "http://localhost:8080"
  provider:
    id: "https://your-institution.org"
    label:
      en: ["Your Institution"]

projects:
  my-project:
    title: "My IIIF Collection"             # Used exactly as collection title (no "Collection" suffix added)
    description: "Description for the viewer"
    metadata:                                 # Applied to both collection AND individual manifests
      - label:
          en: ["Creator"]
        value:
          none: ["Creator Name"]
      - label:
          en: ["Date"]
        value:
          none: ["2024"]
      - label:
          en: ["Subjects"]                   # Will be automatically populated with manifest names
        value:
          en: ["Topic 1", "Topic 2"]         # Your subjects + manifest names will be combined
```

**Note**: 
- Individual manifests inherit the metadata from the collection but keep their titles based on the annotation filename
- The "Subjects" field in collection metadata is automatically populated with all manifest/annotation names
- If you have existing subjects, the manifest names will be added to them

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

## Troubleshooting

```bash
./bootstrap.sh logs                              # View all logs
docker-compose -p my-project logs miiify        # Check specific service
./bootstrap.sh stop && ./bootstrap.sh build my-project  # Restart clean
```

## Performance Tips

- Default builds reuse Docker images (fast)
- Use `--force` only when needed (slow rebuild)
- Each project gets isolated Docker images
- TIFF images: use tiled format for better zoom performance
- Organize content into separate annotation files for better manifest structure
