# IIIF-In-A-Box

Transform images and annotations into a complete IIIF service with viewer, search, and annotation capabilities.

A single bash script wires together five existing open-source containers ([IIPImage](https://iipimage.sourceforge.io/), [Miiify](https://github.com/nationalarchives/miiify), [AnnoSearch](https://github.com/nationalarchives/annosearch), [Quickwit](https://quickwit.io/), [Tamerlane](https://github.com/tamerlaneviewer/tamerlane)) behind nginx. There is no custom server, no database to administer, and no application code to deploy. The script reads your project, generates IIIF manifests and viewer pages, and runs `docker compose up`. That's it.

## Requirements

- Docker
- yq (YAML processor)

```bash
# Debian/Ubuntu (do NOT use apt — it installs an incompatible Python wrapper)
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# macOS
brew install yq
```

## Quick Start

```bash
# 1. Clone the example project (a small medieval manuscript with annotations)
git clone https://github.com/jptmoore/example-iiif-in-a-box-project.git

# 2. Build and start
./bootstrap.sh build --input-dir example-iiif-in-a-box-project

# 3. Open http://localhost:8080/pages/book.html
```

To build your own project, copy the layout of [example-iiif-in-a-box-project](https://github.com/jptmoore/example-iiif-in-a-box-project): a `config.yml`, an `images/` folder, and one annotation folder per image.

## Image Naming

Images use dash-separated names. The number of dashes determines the IIIF structure:

| Pattern | Example | Output |
|---|---|---|
| `{manifest}-{canvas}` | `book-page01.jpg` | `book.json` (Manifest) |
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
  name: book            # determines viewer page filename (book.html)
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
./bootstrap.sh status       # service status
./bootstrap.sh stop         # stop all services
./bootstrap.sh restart      # restart services
./bootstrap.sh logs         # view logs
./bootstrap.sh maintenance  # enable maintenance mode (shows maintenance page)
```

## Services

All services are accessed through nginx. The port defaults to 8080 locally and is derived from the `--hostname` argument (e.g. `--hostname https://example.com` uses port 80):

| URL | Description |
|---|---|
| `/pages/book.html` | IIIF viewer |
| `/iiif/book.json` | IIIF manifest or collection |
| `/miiify/book-page01/?page=0` | Annotations for a canvas |
| `/annosearch/book/search?q=hello` | Content search |

Search results may take a minute or two to appear after a build completes. AnnoSearch hands annotations to Quickwit, which indexes them in the background — the viewer and manifests are available immediately, but `/annosearch/.../search` will return empty results until the first commit lands.

## License

MIT

