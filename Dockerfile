FROM postgres:18

# The PGDG apt repo (already configured in this base image) carries current
# packages for both, so install them straight from there instead of building
# from source.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        postgresql-18-partman \
        postgresql-18-pgvector; \
    rm -rf /var/lib/apt/lists/*
