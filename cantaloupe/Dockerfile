# Use an official base image with OpenJDK 17 (required for Cantaloupe 5.0+)
FROM eclipse-temurin:17-jdk

# Set working directory
WORKDIR /cantaloupe

# Download and extract the JAR from the ZIP
RUN apt-get update && apt-get install -y wget unzip && \
    wget --no-check-certificate -O cantaloupe.zip https://github.com/cantaloupe-project/cantaloupe/releases/download/v5.0.7/cantaloupe-5.0.7.zip && \
    unzip cantaloupe.zip && \
    cp cantaloupe-5.0.7/cantaloupe-5.0.7.jar ./ && \
    rm -rf cantaloupe.zip cantaloupe-5.0.7 && \
    apt-get purge -y wget unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY cantaloupe.properties .

# Expose the default Cantaloupe port (8182)
EXPOSE 8182

# Use a specific user if you want to avoid running as root (optional)
# RUN useradd -m cantaloupe
# USER cantaloupe

# Entry point command
CMD ["java", "-Dcantaloupe.config=cantaloupe.properties", "-Xmx2g", "-jar", "cantaloupe-5.0.7.jar"]
