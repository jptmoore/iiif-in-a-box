# IIIF-in-a-Box Project Setup Guide

The bootstrap script now supports dynamic project creation with custom project names and IIIF manifest URIs.

## Basic Usage

### Default Setup (Demo project)
```bash
./bootstrap.sh build
```

### Custom Project Setup
```bash
./bootstrap.sh --project myproject --uri https://example.com/manifest.json build
```

### Short Options
```bash
./bootstrap.sh -p myproject -u https://example.com/manifest.json build
```

## Command Line Options

### Project Options
- `--project, -p PROJECT_NAME` - Set the project name (default: demo)
- `--uri, -u URI` - Set the IIIF manifest/collection URI
- `--help, -h` - Show help message

### Build Commands
- `build` - Update projects and build/start services (default)
- `build-proxy` - Build with proxy-friendly options (for corporate networks)
- `update-only` - Only update git repositories
- `status` - Show service status
- `stop` - Stop all services
- `restart` - Restart all services
- `logs` - Show service logs

## Examples

### Create a medieval manuscripts project
```bash
./bootstrap.sh --project medieval --uri https://api.library.com/medieval/manifest.json build
```

### Create a demo project with template manifest
```bash
./bootstrap.sh --project demo build
```

### Use proxy-friendly build for corporate networks
```bash
./bootstrap.sh --project corporate -u https://internal.company.com/manifest.json build-proxy
```

### Update only (no build)
```bash
./bootstrap.sh --project myproject update-only
```

## What Gets Created

For each project, the script creates:

### 1. IIIF Manifest (`web/iiif/{project_name}.json`)
- If `--uri` provided: Downloads the IIIF resource (manifest or collection) from the URI
- If no URI provided: Creates a template manifest with empty items array

### 2. HTML Page (`web/pages/{project_name}.html`)
- Responsive HTML page with IIIF viewer
- Branded with TNA-inspired styling
- Links to the project's IIIF manifest
- Accessible at: `http://localhost:8080/pages/{project_name}.html`

## Project Name Requirements

- Must contain only alphanumeric characters, hyphens, and underscores
- Cannot be empty
- Examples: `project1`, `medieval-manuscripts`, `demo_collection`

## URI Options

### External IIIF Resource
```bash
./bootstrap.sh -p myproject -u https://iiif.example.com/manifest.json build
```
- Downloads and uses the external IIIF resource
- Supports both manifests and collections
- Requires curl or wget

### Template Manifest
```bash
./bootstrap.sh -p myproject build
```
- Creates empty template manifest
- You need to manually add canvas items
- Good for starting new projects

## File Structure

After running with project name "myproject":
```
web/
├── iiif/
│   └── myproject.json       # Your project manifest
├── pages/
│   └── myproject.html       # Your project page
└── images/
    └── *.tif                # Image files for IIPImage server
```

## URLs After Setup

- Main interface: `http://localhost:8080`
- Project viewer: `http://localhost:8080/pages/{project_name}.html`
- IIIF manifest: `http://localhost:8080/iiif/{project_name}.json`
- Tamerlane viewer: `http://localhost:8080/viewer/`

## Advanced Usage

### Multiple Projects
You can create multiple projects by running the script multiple times:
```bash
./bootstrap.sh -p project1 -u https://example.com/manifest1.json update-only
./bootstrap.sh -p project2 -u https://example.com/manifest2.json update-only
./bootstrap.sh build
```

### Corporate Proxy Setup
For corporate environments with proxy/firewall restrictions:
```bash
# Configure Docker for corporate proxy
sudo ./configure-docker-proxy.sh

# Build with proxy-friendly options
./bootstrap.sh -p myproject build-proxy
```

## Troubleshooting

### Failed to fetch IIIF resource
- Check URL is accessible
- Verify network/proxy settings
- Try manual download: `curl -s https://example.com/manifest.json`

### Invalid project name
- Use only alphanumeric characters, hyphens, underscores
- No spaces or special characters

### Service startup issues
- Check Docker is running: `docker ps`
- View logs: `./bootstrap.sh logs`
- Check status: `./bootstrap.sh status`

### Corporate network issues
- Use the proxy configuration script: `./configure-docker-proxy.sh`
- Use proxy-friendly build: `./bootstrap.sh build-proxy`

## Integration with Existing Projects

The functionality is designed to be clean and minimal:
- Default project name is "demo" (creates demo.json and demo.html)
- No example files included - only what you create
- Old command syntax still works: `./bootstrap.sh build`
