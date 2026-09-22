# syntax=docker/dockerfile:1
## Stage 1: Build pretix with plugins
FROM pretix/standalone:stable AS pretix-build
# FROM ghcr.io/awsugid/pretix-base-image:latest@sha256:1197017fbe77ad6281115bde6c47fe152c1c1a3e5fcdd667eb8f4d21a8cdf655 AS pretix-build

USER root

# Install git in case it's not present for fetching from private repo
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Install midtransclient for plugin
RUN pip install --upgrade pip && \
    pip install --no-cache-dir midtransclient>=1.4.0

# Install pretix plugins from private repositories using BuildKit secrets
# Token goes into a transient ~/.netrc (git honors it for HTTPS auth), never into
# the URL: keeps the remote URL / pip direct_url clean and layer-cache stable.
RUN --mount=type=secret,id=github_token,required=true \
    printf 'machine github.com\nlogin %s\npassword x-oauth-basic\n' "$(cat /run/secrets/github_token)" > /root/.netrc && \
    chmod 600 /root/.netrc && \
    pip install "git+https://github.com/awsugid/pretix-midtrans.git@v1.0.2" && \
    rm -f /root/.netrc

RUN pip install "git+https://github.com/awsugid/gultix-aws-font.git"

# Pinned by parent-supplied commit SHA (default: main). Changing the ARG only
# invalidates this RUN onward; URL stays token-free so cache keys are stable.
ARG PRETIX_EMAIL_SIGNATURE_REF=main
RUN pip install "git+https://github.com/awsugid/pretix-email-signature.git@${PRETIX_EMAIL_SIGNATURE_REF}"

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
FROM nginx:1.31.1-trixie AS nginx

# Copy the nginx.conf directly
COPY config/nginx.conf /etc/nginx/nginx.conf

COPY --from=pretix-build /pretix/src/pretix/static.dist/ /pretix/src/pretix/static.dist/
