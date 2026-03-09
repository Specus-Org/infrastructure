# =============================================================================
# Specus PostgreSQL 17 Custom Image
# =============================================================================
# Multi-stage build for PostgreSQL 17 with production-ready extensions:
# - pg_stat_statements, uuid-ossp, pg_trgm (contrib)
# - pg_cron (job scheduling)
# - PostGIS (geospatial)
# - ParadeDB pg_search (BM25 full-text search)
# - Apache AGE (graph database)
# - auto_explain (query analysis)
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build Apache AGE from source
# -----------------------------------------------------------------------------
FROM postgres:17-bookworm AS age-builder

ARG AGE_VERSION=1.7.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    ca-certificates \
    postgresql-server-dev-17 \
    libreadline-dev \
    zlib1g-dev \
    flex \
    bison \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN git clone --branch release/PG17/${AGE_VERSION} --depth 1 \
    https://github.com/apache/age.git && \
    cd age && \
    make && \
    make install DESTDIR=/age-install

# -----------------------------------------------------------------------------
# Stage 2: Final PostgreSQL image with all extensions
# -----------------------------------------------------------------------------
FROM postgres:17-bookworm

LABEL org.opencontainers.image.title="Specus PostgreSQL 17"
LABEL org.opencontainers.image.description="PostgreSQL 17 with pg_cron, PostGIS, ParadeDB pg_search, Apache AGE, and contrib extensions"
LABEL org.opencontainers.image.source="https://github.com/adryanev/specus-infrastructure"

# Install contrib extensions and pg_cron
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-contrib \
    postgresql-17-cron \
    postgresql-17-postgis-3 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy Apache AGE from builder stage
COPY --from=age-builder /age-install/usr/lib/postgresql/17/lib/ /usr/lib/postgresql/17/lib/
COPY --from=age-builder /age-install/usr/share/postgresql/17/extension/ /usr/share/postgresql/17/extension/

# Install ParadeDB pg_search
ARG PARADEDB_VERSION=0.21.10
RUN curl -L "https://github.com/paradedb/paradedb/releases/download/v${PARADEDB_VERSION}/postgresql-17-pg-search_${PARADEDB_VERSION}-1PARADEDB-bookworm_amd64.deb" \
    -o /tmp/pg_search.deb && \
    dpkg -i /tmp/pg_search.deb && \
    rm /tmp/pg_search.deb

# Copy custom configuration files
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf

# Copy initialization scripts
COPY init-scripts/ /docker-entrypoint-initdb.d/

# Configure PostgreSQL to use custom config
RUN echo "include = '/etc/postgresql/postgresql.conf'" >> /usr/share/postgresql/postgresql.conf.sample

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pg_isready -U postgres || exit 1

# Expose PostgreSQL port
EXPOSE 5432

# Use custom config on startup
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf", "-c", "hba_file=/etc/postgresql/pg_hba.conf"]
