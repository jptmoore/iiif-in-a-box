# Use an official base image with OpenJDK 17 (required for Cantaloupe 5.0+)
FROM eclipse-temurin:17-jdk

# Set working directory
WORKDIR /cantaloupe

# Install download tools in a separate layer (cached)
RUN apt-get update && apt-get install -y wget unzip && \
    rm -rf /var/lib/apt/lists/*

# Download Cantaloupe in a separate layer (cached unless version changes)
RUN wget --no-check-certificate -O cantaloupe.zip https://github.com/cantaloupe-project/cantaloupe/releases/download/v5.0.7/cantaloupe-5.0.7.zip

# Extract and setup in a separate layer (cached)
RUN unzip cantaloupe.zip && \
    cp cantaloupe-5.0.7/cantaloupe-5.0.7.jar ./ && \
    rm -rf cantaloupe.zip cantaloupe-5.0.7

# Clean up tools (cached)
RUN apt-get purge -y wget unzip && apt-get autoremove -y

# Copy config file (only rebuilds this layer if config changes)
COPY cantaloupe.properties .

# Expose the default Cantaloupe port (8182)
EXPOSE 8182

# Use a specific user if you want to avoid running as root (optional)
# RUN useradd -m cantaloupe
# USER cantaloupe

# Entry point command
CMD ["java", "-Dcantaloupe.config=cantaloupe.properties", "-Xmx2g", "-jar", "cantaloupe-5.0.7.jar"]
