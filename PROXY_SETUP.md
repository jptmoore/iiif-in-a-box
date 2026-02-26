# Corporate Proxy Configuration for IIIF-in-a-Box

This guide helps you configure IIIF-in-a-Box to work in corporate environments with proxy servers and TLS/SSL restrictions.

## Quick Start for Corporate Networks

If you're experiencing TLS handshake timeouts or certificate issues:

```bash
# 1. Configure Docker for proxy environment (requires sudo)
sudo ./configure-docker-proxy.sh

# 2. Build with proxy-friendly options
./bootstrap.sh build-proxy
```

## Common Issues and Solutions

### TLS Handshake Timeout
**Error:** `failed to do request: Head "https://registry-1.docker.io/v2/library/eclipse-temurin/manifests/17-jdk": net/http: TLS handshake timeout`

**Solutions:**
1. Use the Docker proxy configuration script:
   ```bash
   sudo ./configure-docker-proxy.sh
   ```

2. Build with proxy-friendly options:
   ```bash
   ./bootstrap.sh build-proxy
   ```

### Certificate Verification Issues
**Error:** SSL certificate verification failures

**Solutions:**
1. The proxy-friendly build uses `--no-check-certificate` for wget operations
2. Node.js builds use `strict-ssl false` configuration
3. Docker daemon is configured with insecure registries

## Configuration Scripts

### configure-docker-proxy.sh
Configures Docker daemon and client for corporate proxy environments.

**Usage:**
```bash
# Configure Docker (requires sudo)
sudo ./configure-docker-proxy.sh

# Test connectivity
./configure-docker-proxy.sh test

# Show current configuration
./configure-docker-proxy.sh show

# Restore backup configuration
sudo ./configure-docker-proxy.sh restore
```

**What it does:**
- Configures Docker daemon with insecure registries
- Sets up Docker client configuration
- Optionally configures HTTP proxy settings
- Tests Docker connectivity
- Creates backups of existing configurations

### bootstrap.sh (Updated)
The bootstrap script now includes proxy-friendly options.

**New Commands:**
```bash
# Build with proxy-friendly options
./bootstrap.sh build-proxy

# Regular build (default)
./bootstrap.sh build

# Other existing commands still work
./bootstrap.sh status
./bootstrap.sh stop
./bootstrap.sh restart
./bootstrap.sh logs
```

## Files Created/Modified

### New Files:
- `configure-docker-proxy.sh` - Docker proxy configuration script
- `iipimage/Dockerfile` - IIPImage server Dockerfile
- `web/Dockerfile.proxy` - Proxy-friendly web Dockerfile  
- `proxy/docker-compose.proxy.yml` - Proxy-friendly compose file
- `PROXY_SETUP.md` - This documentation

### Modified Files:
- `bootstrap.sh` - Added proxy-friendly build options

## Manual Configuration

If the automated scripts don't work, you can manually configure:

### 1. Docker Daemon Configuration
Create or edit `/etc/docker/daemon.json`:
```json
{
  "insecure-registries": [
    "registry-1.docker.io",
    "docker.io", 
    "index.docker.io"
  ],
  "registry-mirrors": [],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### 2. HTTP Proxy for Docker
Create `/etc/systemd/system/docker.service.d/http-proxy.conf`:
```ini
[Service]
Environment="HTTP_PROXY=http://proxy.company.com:8080"
Environment="HTTPS_PROXY=http://proxy.company.com:8080"
Environment="NO_PROXY=localhost,127.0.0.1,.company.com"
```

### 3. Restart Docker
```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

## Environment Variables

You can also set these environment variables before running bootstrap.sh:

```bash
# Skip TLS verification for Docker builds
export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0

# For npm/Node.js builds
export npm_config_strict_ssl=false
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Then run
./bootstrap.sh build-proxy
```

## Troubleshooting

### Check Docker Configuration
```bash
./configure-docker-proxy.sh show
```

### Test Docker Connectivity
```bash
./configure-docker-proxy.sh test
```

### Manual Image Pull Test
```bash
docker pull alpine:latest
```

### Check Service Logs
```bash
./bootstrap.sh logs
```

### Reset Configuration
```bash
sudo ./configure-docker-proxy.sh restore
sudo systemctl restart docker
```

## Security Considerations

The proxy-friendly configurations disable some security features:
- TLS certificate verification is bypassed
- Insecure registries are allowed
- npm strict-ssl is disabled

These settings should only be used in trusted corporate environments where necessary.

## Support

If you continue to experience issues:

1. Check your corporate firewall/proxy settings
2. Verify Docker service is running: `systemctl status docker`
3. Check Docker logs: `journalctl -u docker.service`
4. Contact your IT department for proxy configuration details
