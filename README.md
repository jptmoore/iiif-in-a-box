# IIIF-In-A-Box v2

Transform images and annotations into a complete IIIF service with viewer, search, and annotation capabilities.

## Requirements

- Docker & Docker Compose v2
- Git
- yq (YAML processor) - [Installation guide](https://github.com/mikefarah/yq)

**Installing yq:**
```bash
# macOS
brew install yq

# Linux
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

**Apple Silicon (M1/M2/M3):**
- Platform constraints configured automatically
- Some services use AMD64 emulation via Rosetta 2

**Authentication:**
Tamerlane images may require GitHub authentication:
```bash
docker login ghcr.io -u YOUR_GITHUB_USERNAME
```

## Quick Start

```bash
# 1. Create a minimal project
mkdir -p /tmp/my-iiif-project/images
cat > /tmp/my-iiif-project/config.yml << 'EOF'
project:
  name: demo
  title: "My First IIIF Collection"
  description: "Testing IIIF-in-a-Box"
EOF

# 2. Add images (use dash-separated names)
cp your-image1.jpg /tmp/my-iiif-project/images/demo-page01.jpg
cp your-image2.jpg /tmp/my-iiif-project/images/demo-page02.jpg

# 3. Build and start
./bootstrap.sh build --input-dir /tmp/my-iiif-project

# 4. Open http://localhost:8080/pages/demo.html
```

## Input Directory Structure

### Organizing Your Images

Use dashes to encode hierarchy in flat filenames. This mirrors the Miiify annotation server's container structure.

**The Simple Rule:**
1. Name images: `manifest-canvas.extension` (or `collection-manifest-canvas.extension` for hierarchy)
2. Create annotation folders: match the image basename exactly
3. Done.

**Single Manifest:**
```
my-project/
├── config.yml
├── images/
│   ├── mybook-page01.jpg
│   └── mybook-page02.jpg
└── annotations/
    ├── mybook-page01/
    │   └── annotation-1.json
    └── mybook-page02/
        └── annotation-2.json
```
→ Creates: **mybook.json** (Manifest with 2 canvases)

**Collection with Manifest:**
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

## How It Works: Images → IIIF Hierarchy

### Structure Detection

The system analyzes your image filenames to automatically create the correct IIIF structure based on dash-separated naming patterns.

### Dash-Separated Naming

**Pattern (single manifest):** `{manifest}-{canvas}.{ext}`

Example: `mybook-page01.jpg`
- Manifest: `mybook`
- Canvas: `page01`

**Pattern (collection + manifest):** `{collection}-{manifest}-{canvas}.{ext}`

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
4. Creates Collections (for prefixes) and Manifests (for leaves)
5. Sorts canvases using lexical/alphabetical sort

### File Ordering (Canvas Sequence)

**Images within a Manifest are automatically sorted using lexical/alphabetical sort**, consistent with the Miiify annotation server sorting. This requires proper file naming:

✅ **Zero-padded numbers (REQUIRED):** `0001, 0002, 0003... 0100, 0101`  
❌ **Unpadded numbers:** `1, 2, 3... 10` → sorts incorrectly as `1, 10, 11, 2`  
✅ **Consistent alphanumeric prefixes:** `page0001, page0002... page0010`

**Examples:**

```
# Correct (zero-padded):
domesday-lincolnshire-0680.tif  →  Canvas 1
domesday-lincolnshire-0684.tif  →  Canvas 2
domesday-lincolnshire-0685.tif  →  Canvas 3
domesday-lincolnshire-0689.tif  →  Canvas 4
domesday-lincolnshire-0690.tif  →  Canvas 5

# Incorrect (unpadded):
page1.jpg, page10.jpg, page100.jpg, page2.jpg, page20.jpg  # WRONG ORDER
```

**Required practices for correct ordering:**

1. **ALWAYS use zero-padding for numeric sequences:**
   - ✅ Required: `page0001.jpg, page0002.jpg, page0010.jpg, page0100.jpg`
   - ❌ Wrong: `page1.jpg, page2.jpg, page10.jpg, page100.jpg` (sorts as 1, 10, 100, 2)

2. **Be consistent with padding width:**
   - ✅ Good: `0001, 0002... 0999` (all 4 digits)
   - ❌ Wrong: `001, 02, 3, 0010` (inconsistent widths)

3. **For folio numbering (recto/verso), use zero-padded prefix:**
   - ✅ Good: `001-123r.tif, 002-123v.tif, 003-124r.tif`
   - ✅ Good: `0123r.tif, 0123v.tif, 0124r.tif` (r < v alphabetically)

4. **Control ordering explicitly with sequence prefixes:**
   ```
   001-frontcover.tif
   002-titlepage.tif
   003-chapter1-page01.tif
   004-chapter1-page02.tif
   ```

**Note:** Collections, sub-collections, and annotations all use lexical/alphabetical sorting for consistency.

### Canvas Naming
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

**Metadata and Provider are automatically included** in your top-level Collection or Manifest. They are converted to IIIF-compliant JSON and added to the generated IIIF resources.

**Note:** The `yq` tool is required to parse YAML configuration. The build will fail if yq is not installed and your config contains metadata or provider sections.

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

**Apple Silicon (M1/M2/M3):**
- Platform constraints configured automatically
- IIPImage, Miiify, AnnoSearch use AMD64 emulation
- Tamerlane runs natively on ARM64

## Troubleshooting

**Services won't start:**
```bash
./bootstrap.sh stop
./bootstrap.sh build --input-dir /path/to/input
```

**Search not working:**
- Wait ~10 seconds for indexing to complete
- Verify manifest exists: `ls output/web/iiif/`

**Viewer not loading:**
- Authenticate with GitHub: `docker login ghcr.io -u YOUR_GITHUB_USERNAME`
- Rebuild: `./bootstrap.sh stop && ./bootstrap.sh build --input-dir /path/to/input`

## Architecture

**Components:**

- **nginx** - Reverse proxy & static files
- **IIPImage** (`iipsrv/iipsrv:latest`) - IIIF Image API 2.0/3.0 server [AMD64]
- **Miiify** (`ghcr.io/nationalarchives/miiify:latest`) - W3C Web Annotation server with Git storage [AMD64]
- **AnnoSearch** (`ghcr.io/nationalarchives/annosearch:latest`) - IIIF Content Search API [AMD64]
- **Quickwit** (`quickwit/quickwit`) - Search engine
- **Tamerlane** (`ghcr.io/tamerlaneviewer/tamerlane:latest`) - IIIF viewer [ARM64/AMD64]

All services communicate on Docker network `iiif-network`. Generated content is volume-mounted from `./output/`.
