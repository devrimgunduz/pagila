#!/bin/bash

pg_restore /docker-entrypoint-initdb.d/pagila-data-apt-jsonb.backup -d postgres

pg_restore /docker-entrypoint-initdb.d/pagila-data-yum-jsonb.backup -d postgres