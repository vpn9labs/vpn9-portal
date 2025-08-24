# syntax=docker/dockerfile:1.9.0@sha256:fe40cf4e92cd0c467be2cfc30657a680ae2398318afd50b0c80585784c604f28
# check=error=true

# Reproducible Build Dockerfile for VPN9 Portal
# This Dockerfile ensures deterministic, reproducible builds
# Build timestamp and metadata are controlled for reproducibility
#
# This is the default Dockerfile used by:
# - Kamal deployments (kamal deploy)
# - Reproducible builds (scripts/reproducible-build.sh)
# - GitHub Actions CI/CD
#
# For development, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Fixed base image with SHA256 digest for reproducibility
ARG RUBY_VERSION=3.4.5
FROM docker.io/library/ruby:${RUBY_VERSION}-slim@sha256:0d2adfa1930d67ee79e5d16c3610f4fbed43c98e98dbda14c2811b8197211c74 AS base

# Label for Kamal
LABEL service="vpn9-portal"


# Set reproducible build timestamp (default to a fixed past date)
ARG SOURCE_DATE_EPOCH=1700000000
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}

# Rails app lives here
WORKDIR /rails

# Install base packages with pinned versions for reproducibility
# Using Debian 13 (trixie) package versions
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        curl=8.14.1-2 \
        libjemalloc2=5.3.0-3 \
        libvips42t64=8.16.1-1+b1 \
        sqlite3=3.46.1-7 \
        busybox=1:1.37.0-6+b3 && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Set production environment with reproducible settings
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    BUNDLE_FROZEN="true" \
    TZ="UTC" \
    LANG="C.UTF-8" \
    LC_ALL="C.UTF-8"

# Build stage
FROM base AS build

# Install build dependencies with pinned versions  
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        build-essential=12.12 \
        git=1:2.47.2-0.2 \
        libyaml-dev=0.2.5-2 \
        pkg-config=1.8.1-4 \
        unzip=6.0-29 && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install Bun with specific version and checksum
ENV BUN_INSTALL=/usr/local/bun
ENV PATH=/usr/local/bun/bin:$PATH
ARG BUN_VERSION=1.2.19
ARG BUN_SHA256=c3d3c14e9a5ec83ff67d0acfe76e4315ad06da9f34f59fc7b13813782caf1f66
RUN curl -fsSL -o bun.zip https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-x64.zip && \
    echo "${BUN_SHA256}  bun.zip" | sha256sum -c - && \
    unzip bun.zip -d /tmp && \
    mkdir -p /usr/local/bun/bin && \
    mv /tmp/bun-linux-x64/bun /usr/local/bun/bin/bun && \
    rm -rf bun.zip /tmp/bun-linux-x64 && \
    chmod +x /usr/local/bun/bin/bun && \
    ln -s /usr/local/bun/bin/bun /usr/local/bun/bin/bunx

# Copy dependency files
COPY --link Gemfile Gemfile.lock ./
COPY --link package.json bun.lock ./

# Install gems with frozen lockfile
RUN bundle install --jobs=$(nproc) --retry=3 && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Install node modules with frozen lockfile
RUN --mount=type=cache,target=/root/.bun/install/cache,sharing=locked \
    bun install --frozen-lockfile

# Copy application code
COPY --link . .

# Remove non-deterministic files and large unnecessary files
RUN rm -rf .git .github .gitignore .dockerignore \
    log/* tmp/* storage/* \
    node_modules/.cache \
    public/packs-test

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Debug: Check bun installation
RUN which bun && bun --version

# Build JavaScript and CSS assets
RUN bun run build && bun run build:css

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Strip timestamps from compiled assets for reproducibility (only if directory exists)
RUN if [ -d public/assets ]; then \
      find public/assets -type f -exec touch -d "@${SOURCE_DATE_EPOCH}" {} \; ; \
    fi

# Clean up build artifacts to reduce image size
# Keep app/assets/builds which contains compiled CSS and JS
RUN rm -rf node_modules tmp/cache vendor/bundle/ruby/*/cache \
    test spec .rspec .rubocop.yml .eslintrc \
    app/assets/stylesheets app/assets/images app/assets/config \
    vendor/assets lib/assets \
    tmp/* log/* storage/* \
    package.json bun.lock postcss.config.js \
    .bundle/config

# Final stage
FROM base

# Copy built artifacts including bun
COPY --from=build --link "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build --link /usr/local/bun /usr/local/bun
COPY --from=build --link /rails /rails

# Ensure bun is in PATH
ENV BUN_INSTALL=/usr/local/bun
ENV PATH=/usr/local/bun/bin:$PATH

# Create necessary directories that were removed during cleanup
RUN mkdir -p tmp/pids tmp/cache log storage && \
    touch log/production.log

# Ensure integrity verifier is executable
RUN chmod +x /rails/bin/docker-entrypoint || true && \
    chmod +x /rails/bin/verify-build-integrity || true

# Create non-root user with fixed UID/GID
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R 1000:1000 db log storage tmp

# Set reproducible file timestamps (only for critical directories)
RUN touch -d "@${SOURCE_DATE_EPOCH}" /rails /rails/public /rails/public/assets 2>/dev/null || true

ARG BUILD_VERSION
ARG BUILD_COMMIT
ARG BUILD_TIMESTAMP

# Bake non-sensitive build metadata into a read-only file for in-container attestation
# Also compute a deterministic filesystem hash over critical paths and embed as fs_hash
RUN mkdir -p /usr/share/vpn9 && \
    FS_HASH=$( \
      set -eu; \
      LANG=C; LC_ALL=C; export LANG LC_ALL; \
      paths="/rails/app /rails/lib /rails/config"; \
      existing=""; \
      for p in $paths; do [ -e "$p" ] && existing="$existing $p"; done; \
      if [ -n "$existing" ]; then \
        find $existing -type f -not -path "/rails/config/environments/development.rb" -not -path "/rails/config/environments/test.rb" -print0 \
          | sort -z \
          | xargs -0 sha256sum \
          | sha256sum \
          | awk '{print $1}'; \
      fi \
    ) && \
    printf '{ "version": "%s", "commit": "%s", "created": "%s", "fs_hash": "%s" }\n' "$BUILD_VERSION" "$BUILD_COMMIT" "$BUILD_TIMESTAMP" "$FS_HASH" > /usr/share/vpn9/build-info.json && \
    chmod 0444 /usr/share/vpn9/build-info.json

USER 1000:1000

ENV BUILD_VERSION=${BUILD_VERSION} \
    BUILD_COMMIT=${BUILD_COMMIT} \
    BUILD_TIMESTAMP=${BUILD_TIMESTAMP}

LABEL org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.revision="${BUILD_COMMIT}" \
      org.opencontainers.image.created="${BUILD_TIMESTAMP}" \
      org.opencontainers.image.source="https://github.com/vpn9labs/vpn9-portal" \
      org.opencontainers.image.vendor="VPN9" \
      org.opencontainers.image.title="VPN9 Portal" \
      org.opencontainers.image.description="Reproducible build of VPN9 Portal"

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
