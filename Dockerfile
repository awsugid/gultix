# syntax=docker/dockerfile:1
## Stage 1: Build pretix with plugins
FROM pretix/standalone:stable AS pretix-build

USER root

# Install git in case it's not present for fetching from private repo
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Install midtransclient for plugin
RUN pip install --upgrade pip && \
    pip install --no-cache-dir midtransclient>=1.4.0

# Install pretix plugins from private repositories using BuildKit secrets
RUN --mount=type=secret,id=github_token \
    TOKEN=$(cat /run/secrets/github_token) && \
    pip install "git+https://${TOKEN}@github.com/awsugid/pretix-midtrans.git"

RUN pip install "git+https://github.com/awsugid/gultix-aws-font.git"

# Collect static files for all plugins
RUN pretix collectstatic --no-input

# Set proper permissions for source files
RUN chown -R pretixuser:pretixuser /pretix/src/

# Ensure /data directory exists with proper permissions
RUN mkdir -p /data && \
    chmod 755 /data && \
    chown -R pretixuser:pretixuser /data

# Set PYTHONPATH for plugin
ENV PYTHONPATH=/pretix/src

EXPOSE 80

USER pretixuser

ENTRYPOINT ["pretix"]
# CMD ["all"]

## Stage 2: Nginx with static files baked in from the pretix build
FROM nginx:latest AS nginx

# Copy the nginx.conf directly
COPY config/nginx.conf /etc/nginx/nginx.conf

COPY --from=pretix-build /pretix/src/pretix/static.dist/ /pretix/src/pretix/static.dist/
