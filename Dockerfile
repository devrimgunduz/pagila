FROM postgres:18

# Neither pg_partman nor pgvector is in the postgres image or the PGDG apt
# repo for every release, so build the exact versions from source instead
# of depending on package availability.
ARG PG_PARTMAN_VERSION=5.5.0
ARG PGVECTOR_VERSION=0.8.6

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        postgresql-server-dev-18 \
        git \
        ca-certificates; \
    git clone --branch "v${PG_PARTMAN_VERSION}" --depth 1 \
        https://github.com/pgpartman/pg_partman.git /tmp/pg_partman; \
    make -C /tmp/pg_partman install; \
    rm -rf /tmp/pg_partman; \
    git clone --branch "v${PGVECTOR_VERSION}" --depth 1 \
        https://github.com/pgvector/pgvector.git /tmp/pgvector; \
    make -C /tmp/pgvector install; \
    rm -rf /tmp/pgvector; \
    apt-get purge -y --auto-remove build-essential postgresql-server-dev-18 git; \
    rm -rf /var/lib/apt/lists/*
