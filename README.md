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
./bootstrap.sh build                           # Build your project (auto-detected from YAML)
./bootstrap.sh build --force                   # Force complete rebuild (slow)
./bootstrap.sh status                          # Show service status  
./bootstrap.sh stop                            # Stop services
./bootstrap.sh restart                         # Restart services
./bootstrap.sh logs                            # View logs
```

**Note**: The system automatically detects and uses the single project defined in `config/projects.yml`. 

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

**Critical Requirements**: 
- **Exactly one project** - Multiple projects will cause build failure
- Annotation files in `web/annotations/` are **required** - build will fail if directory is empty
- Your annotation files are **preserved exactly as provided** - no modifications made
- Generated manifests appear in `web/iiif/` - these are created from your source annotations

## User Workflow

1. **Setup Configuration**: Create/edit `config/projects.yml` with exactly one project
2. **Add Content**: 
   - Place your images in `web/images/`
   - Place your annotation JSON files directly in `web/annotations/`
3. **Build**: Run `./bootstrap.sh build`
4. **Access**: Visit `http://localhost:8080/pages/your-project-name.html`

**File Preservation**: Your annotation files in `web/annotations/` are never modified. The system reads them to generate IIIF manifests in `web/iiif/`, but your source files remain untouched.

## Services

- **🌐 nginx** (8080) - Main access point
- **📄 Apache** - Viewer at `/viewer/`
- **🖼️ Cantaloupe** - IIIF Image API at `/cantaloupe/`
- **🔍 AnnoSearch** - Search at `/annosearch/`
- **📝 Miiify** - Annotation server at `/miiify/`

## Generated Output

- **📁 IIIF Collection** - Main collection JSON in `web/iiif/`
- **📋 IIIF Manifests** - Individual manifests generated from your annotation files
- **📄 HTML Viewer** - Project-specific viewer page at `/pages/your-project.html`
- **🔍 Search Index** - Full-text searchable annotations
- **🐳 Docker Environment** - Project-named containers for isolation

**Note**: All generated files appear in `web/iiif/` while your source files in `web/annotations/` remain unchanged.

## Requirements

- **git, docker, docker-compose**
- **At least one annotation file** in `web/annotations/` (build will fail if empty)
- First build: ~5-10 minutes, subsequent: ~1-2 minutes

## Troubleshooting

```bash
# Common issues and solutions
./bootstrap.sh logs                              # View all service logs

# If build fails due to multiple projects in YAML:
# Edit config/projects.yml and keep only one project

# If build fails due to empty annotations:
# Add your annotation JSON files to web/annotations/

# Clean restart:
./bootstrap.sh stop && ./bootstrap.sh build     

# Check specific service (replace 'your-project' with actual name):
docker-compose -p your-project logs miiify      
```

**Common Build Failures**:
- Multiple projects in `config/projects.yml` → Keep only one project
- Empty `web/annotations/` directory → Add your annotation JSON files  
- Missing `config/projects.yml` → Create configuration file

## Performance Tips

- Default builds reuse Docker images (fast)
- Use `--force` only when needed (slow rebuild)
- Each project gets isolated Docker images
- TIFF images: use tiled format for better zoom performance
- Organize content into separate annotation files for better manifest structure