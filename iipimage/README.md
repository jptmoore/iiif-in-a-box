# IIPImage Server Configuration

This directory contains documentation for the IIPImage server, a lightweight and high-performance IIIF Image API server.

## Why IIPImage?

IIPImage was chosen to replace Cantaloupe because:
- **Lightweight**: Much smaller resource footprint than Java-based Cantaloupe
- **Already dockerized**: Official Docker image available at [iipsrv/iipsrv](https://hub.docker.com/r/iipsrv/iipsrv)
- **Fast**: Written in C++ for optimal performance
- **IIIF compliant**: Supports IIIF Image API 2.0 and 3.0

## No Custom Build Required

We use the official `iipsrv/iipsrv:latest` image directly from Docker Hub - no custom Dockerfile needed!

## Documentation

- Project homepage: https://iipimage.sourceforge.io/
- Server documentation: https://iipimage.sourceforge.io/documentation/server/
- Docker image: https://hub.docker.com/r/iipsrv/iipsrv

## Configuration

The server is configured entirely via environment variables in the docker-compose.yml file:

- `FILESYSTEM_PREFIX=/images/` - Path to image files
- `MAX_IMAGE_CACHE_SIZE=1000` - Maximum number of images to cache in memory
- `JPEG_QUALITY=90` - JPEG output quality (1-100)
- `MAX_CVT=5000` - Maximum image dimensions for region extraction
- `VERBOSITY=2` - Log verbosity level (0-6)

## URLs

Images are served via the IIIF Image API:
- IIIF v2: `http://localhost:8080/iiif/2/{image-id}/{region}/{size}/{rotation}/{quality}.{format}`
- IIIF v3: `http://localhost:8080/iiif/3/{image-id}/{region}/{size}/{rotation}/{quality}.{format}`

## Image Formats Supported

- JPEG
- TIFF (including pyramidal TIFF)
- PNG

For optimal performance, use pyramidal TIFF images.
