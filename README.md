# IIIF-In-A-Box

Transforms images and annotations into IIIF Collections with viewer, search, and annotation capabilities.

**Input:** Images + Annotation files + YAML configuration  
**Output:** IIIF Collections with manifests, viewer, and search

## Quick Start

```bash
# 1. Configure your project in config/projects.yml
# 2. Add images to web/images/
# 3. Add annotation files to web/annotations/
# 4. Build
./bootstrap.sh build
```

## Architecture

- **📄 Annotation Preservation** - Files in `web/annotations/` are used exactly as provided
- **📋 Manifest Generation** - Annotations processed into IIIF manifests in `web/iiif/`
- **🔍 Integrated Search** - Full-text search across all annotations
- **🐳 Project-specific Naming** - Docker containers use your project name

## Content Structure
```
config/projects.yml      ← Project configuration (exactly one project required)
web/images/             ← Your image files (TIFF, JPG, PNG, etc.)
web/annotations/        ← Your annotation files (placed here by you, preserved as-is)
web/iiif/              ← Generated IIIF collections + manifests (auto-created)
```

**Important**: 
- Place annotation files directly in `web/annotations/` - they will NOT be modified
- The system generates IIIF manifests in `web/iiif/` from your source annotations

## Commands

```bash
# Basic commands
./bootstrap.sh build                           # Build your project (auto-detected from YAML)
./bootstrap.sh build --force                   # Force complete rebuild (slow)
./bootstrap.sh status                          # Show service status  
./bootstrap.sh stop                            # Stop services
./bootstrap.sh restart                         # Restart services
./bootstrap.sh logs                            # View logs

# Hostname configuration for deployment
./bootstrap.sh build --hostname http://localhost:8080     # Local development (default)
./bootstrap.sh build --hostname http://18.135.130.106:8080  # VM deployment
./bootstrap.sh build --hostname https://your-domain.com     # Custom domain deployment
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
  your-project-name:                            # Change this to your project name
    title: "My IIIF Collection"                 # Used exactly as collection title
    description: "Description for the viewer"
    metadata:                                   # Applied to both collection AND individual manifests
      - label:
          en: ["Creator"]
        value:
          none: ["Creator Name"]
      - label:
          en: ["Date"]
        value:
          none: ["2024"]
      - label:
          en: ["Subjects"]                     # Will be automatically populated with manifest names
        value:
          en: ["Topic 1", "Topic 2"]           # Your subjects + manifest names will be combined
```


## Services

- **🌐 nginx** (8080) - Main access point
- **📄 Apache** - Viewer at `/viewer/`
- **🖼️ IIPImage** - IIIF Image API at `/iiif/`
- **🔍 AnnoSearch** - Search at `/annosearch/`
- **📝 Miiify** - Annotation server at `/miiify/`


## Requirements

- **git, docker, docker-compose**
- **At least one annotation file** in `web/annotations/` (build will fail if empty)

