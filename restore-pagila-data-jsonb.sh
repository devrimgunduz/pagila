#!/bin/bash

pg_restore /docker-entrypoint-initdb.d/pagila-data-apt-jsonb.backup -d "$POSTGRES_DB"

pg_restore /docker-entrypoint-initdb.d/pagila-data-yum-jsonb.backup -d "$POSTGRES_DB"