FROM postgres:18

# pg_partman is not in the postgres image or the PGDG apt repo for every
# release, so build the exact version from source instead of depending on
# package availability.
ARG PG_PARTMAN_VERSION=5.5.0

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
    apt-get purge -y --auto-remove build-essential postgresql-server-dev-18 git; \
    rm -rf /var/lib/apt/lists/*
