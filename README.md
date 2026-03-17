# IIIF-In-A-Box

Transform images and annotations into a complete IIIF service with viewer, search, and annotation capabilities.

## Requirements

- Docker
- yq (YAML processor)

```bash
# Debian/Ubuntu
sudo apt-get install -y yq

# macOS
brew install yq
```

## Quick Start

```bash
# 1. Create a project directory
mkdir -p my-project/images

cat > my-project/config.yml << 'EOF'
project:
  name: mybook
  title: "My Book"
  description: "A digitised book"
EOF

# 2. Add images using dash-separated names: {manifest}-{canvas}.ext
cp page01.jpg my-project/images/mybook-page01.jpg
cp page02.jpg my-project/images/mybook-page02.jpg

# 3. Build and start
./bootstrap.sh build --input-dir my-project

# 4. Open http://localhost:8080/pages/mybook.html
```

## Image Naming

Images use dash-separated names. The number of dashes determines the IIIF structure:

| Pattern | Example | Output |
|---|---|---|
| `{manifest}-{canvas}` | `mybook-page01.jpg` | `mybook.json` (Manifest) |
| `{collection}-{manifest}-{canvas}` | `domesday-lincoln-0001.tif` | `domesday.json` (Collection) → `lincoln.json` (Manifest) |
| `{col}-{sub}-{manifest}-{canvas}` | `archive-vol1-ch1-page01.tif` | `archive.json` → `vol1.json` → `ch1.json` (Manifest) |

The last segment is always the canvas name. All other segments become Collections, except the second-to-last which becomes the Manifest.

**Use zero-padded numbers** to ensure correct canvas order: `page001`, `page002`, not `page1`, `page2`.

## Canvas IDs

Canvas IDs are taken directly from the `target` (or `target.source`) in your annotation files, with any fragment selector stripped. This guarantees the manifest canvas IDs always match what your annotations reference.

If a canvas has no annotations, an ID is generated from the hostname and image name.

## Annotations

Annotation folders must match the full image name (without extension):

```
images/domesday-lincoln-0001.tif  →  annotations/domesday-lincoln-0001/
```

Each folder can contain one or more annotation JSON files in W3C Web Annotation format.

## config.yml

```yaml
project:
  name: mybook          # determines viewer page filename (mybook.html)
  title: "My Book"
  description: "..."

  metadata:             # optional, added to top-level manifest/collection
    - label:
        en: ["Creator"]
      value:
        none: ["Your Name"]

provider:               # optional
  id: "https://your-institution.org"
  type: "Agent"
  label:
    en: ["Your Institution"]
```

## Commands

```bash
./bootstrap.sh build --input-dir /path/to/project   # build and start
./bootstrap.sh build --input-dir /path --hostname https://yourdomain.com
./bootstrap.sh status     # service status
./bootstrap.sh stop       # stop all services
./bootstrap.sh restart    # restart services
./bootstrap.sh logs       # view logs
```

## Services

All services are accessed through nginx (default port 8080, configurable via `NGINX_PORT`):

| URL | Description |
|---|---|
| `/pages/mybook.html` | IIIF viewer |
| `/iiif/mybook.json` | IIIF manifest or collection |
| `/miiify/mybook-page01/?page=0` | Annotations for a canvas |
| `/annosearch/mybook/search?q=hello` | Content search |

## License

MIT

