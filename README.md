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

- **📁 Project = IIIF Collection** (from `config/projects.yml`)
- **📄 Annotation File = IIIF Manifest** (each JSON file in `web/annotations/`)
- **🔍 Collection-level Search** across all manifests
- **🐳 Project-specific Docker images** (uses your project name from YAML)

## Content Structure
```
config/projects.yml      ← Project configuration (required)
web/images/             ← Your images
web/annotations/        ← Annotation files (each → manifest)
web/iiif/              ← Generated collections + manifests
```

## Commands

```bash
./bootstrap.sh build                           # Build your project (from YAML)
./bootstrap.sh build --force                   # Force complete rebuild
./bootstrap.sh status                          # Show service status  
./bootstrap.sh stop                            # Stop services
./bootstrap.sh restart                         # Restart services
./bootstrap.sh logs                            # View logs
```

**Note**: The system uses the single project defined in `config/projects.yml`

## Configuration

YAML configuration in `config/projects.yml` (must contain exactly one project):

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

**Notes**: 
- Only one project allowed in the YAML file
- Individual manifests inherit metadata but keep titles based on annotation filenames
- "Subjects" field automatically includes all manifest/annotation names
- Docker containers will be named with your project name prefix

## Services

- **🌐 nginx** (8080) - Main access point
- **📄 Apache** - Viewer at `/viewer/`
- **🖼️ Cantaloupe** - IIIF Image API at `/cantaloupe/`
- **🔍 AnnoSearch** - Search at `/annosearch/`
- **📝 Miiify** - Annotation server at `/miiify/`

## Generated Output

- **📁 IIIF Collection** (`project-collection.json`) - Contains all manifests
- **📋 IIIF Manifests** (`project-manifest-*.json`) - One per annotation file
- **📄 HTML Pages** - Project-specific viewer pages  
- **🔍 Search Index** - Full-text searchable collection
- **🐳 Project Docker Images** - Named with project prefix

## Requirements

- **git, docker, docker-compose**
- First build: ~5-10 minutes, subsequent: ~1-2 minutes

## Troubleshooting

```bash
./bootstrap.sh logs                              # View all logs
docker-compose -p your-project logs miiify      # Check specific service (use your project name)
./bootstrap.sh stop && ./bootstrap.sh build     # Restart clean
```

## Performance Tips

- Default builds reuse Docker images (fast)
- Use `--force` only when needed (slow rebuild)
- Each project gets isolated Docker images
- TIFF images: use tiled format for better zoom performance
- Organize content into separate annotation files for better manifest structure