# Build stage for Tamerlane React app
FROM node:20-slim as tamerlane-builder

WORKDIR /app

# Copy package files first for better caching
COPY tamerlane/package*.json ./
RUN npm ci --only=production

# Copy source and build
COPY tamerlane .
ENV PUBLIC_URL=/viewer
ENV NODE_ENV=production
RUN npm run build

# Main Apache stage
FROM httpd:2.4-alpine

# Skip installing curl/wget due to SSL issues - use Apache built-in health check

# Enable required Apache modules
RUN sed -i 's/#LoadModule rewrite_module/LoadModule rewrite_module/' /usr/local/apache2/conf/httpd.conf && \
    sed -i 's/#LoadModule headers_module/LoadModule headers_module/' /usr/local/apache2/conf/httpd.conf

# Create conf.d directory structure
RUN mkdir -p /usr/local/apache2/conf/conf.d

# Copy Apache configuration
COPY iiif-in-a-box/web/apache-cors.conf /usr/local/apache2/conf/conf.d/cors.conf
COPY iiif-in-a-box/web/apache-security.conf /usr/local/apache2/conf/conf.d/security.conf

# Include conf.d directory
RUN echo "IncludeOptional conf/conf.d/*.conf" >> /usr/local/apache2/conf/httpd.conf

# Copy specific web content directories only
COPY iiif-in-a-box/web/index.html /usr/local/apache2/htdocs/
COPY iiif-in-a-box/web/iiif /usr/local/apache2/htdocs/iiif/
COPY iiif-in-a-box/web/images /usr/local/apache2/htdocs/images/
COPY iiif-in-a-box/web/pages /usr/local/apache2/htdocs/pages/

# Copy IIIF-in-a-Box logo to web root
COPY iiif-in-a-box/assets/iiif-in-a-box.png /usr/local/apache2/htdocs/

# Copy TNA logo to web root
COPY iiif-in-a-box/assets/tna-square-logo.svg /usr/local/apache2/htdocs/assets/

# Copy built Tamerlane React app
COPY --from=tamerlane-builder /app/build /usr/local/apache2/htdocs/viewer

# Create non-root user for security
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup && \
    chown -R appuser:appgroup /usr/local/apache2/htdocs/ && \
    chown -R appuser:appgroup /usr/local/apache2/logs/

# Health check using Apache's built-in config test
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD httpd -t

EXPOSE 80

# Switch to non-root user
USER appuser

CMD ["httpd-foreground"]