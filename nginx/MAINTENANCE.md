# Maintenance Mode

This directory contains the configuration for maintenance mode - a minimal setup that shows users a maintenance notice while services are being updated or repaired.

## Overview

Maintenance mode stops all IIIF services and runs only a minimal nginx server that displays a maintenance page to users. This ensures:
- Users are informed the service is temporarily unavailable
- Minimal resource usage during maintenance
- Proper HTTP 503 status codes for search engines
- Clean shutdown of all services

## Usage

### Enable Maintenance Mode

```bash
./bootstrap.sh maintenance
```

This will:
1. Stop all running IIIF services (web, iipimage, annosearch, miiify, quickwit)
2. Start a minimal nginx container with the maintenance page
3. Make the maintenance page available at http://localhost:8080

### Bring Services Back Online

```bash
./bootstrap.sh build
```

This will:
1. Automatically detect and stop maintenance mode
2. Build and start all IIIF services

## Files

- `docker-compose.maintenance.yml` - Minimal docker-compose with nginx only
- `conf/maintenance.conf` - Nginx configuration for maintenance mode
- `../templates/maintenance.html` - The maintenance page shown to users

## Customization

### Customize the Maintenance Page

Edit [templates/maintenance.html](../templates/maintenance.html) to customize:
- Message to users
- Estimated downtime
- Contact information
- Styling and branding

### Customize HTTP Headers

Edit [nginx/maintenance.conf](nginx/maintenance.conf) to customize:
- `Retry-After` header (default: 300 seconds / 5 minutes)
- Security headers
- Other HTTP response headers

## Technical Details

### HTTP Status Code

The maintenance page returns **HTTP 503 Service Unavailable** which:
- Tells search engines the downtime is temporary
- Prevents indexing of the maintenance page
- Includes `Retry-After` header for automated retry logic

### Port Binding

The maintenance nginx binds to the same ports as the normal setup:
- Port 8080 (primary)
- Port 80 (if you have permission)

### Health Check

The `/health` endpoint returns `503 maintenance` during maintenance mode, allowing load balancers and monitoring systems to detect the maintenance state.

## Workflow Examples

### Planned Maintenance

```bash
# 1. Enable maintenance mode
./bootstrap.sh maintenance

# 2. Perform updates, backups, etc.
# ... your maintenance tasks ...

# 3. Bring services back online
./bootstrap.sh build
```

### Emergency Response

```bash
# Immediately stop all services and show maintenance page
./bootstrap.sh maintenance

# When ready, bring services back
./bootstrap.sh build
```

## Monitoring

Check maintenance mode status:
```bash
# Check if maintenance mode is active
docker ps | grep iiif-nginx-maintenance

# Check the maintenance page
curl -I http://localhost:8080
# Should return: HTTP/1.1 503 Service Unavailable

# View maintenance nginx logs
docker logs iiif-nginx-maintenance
```
