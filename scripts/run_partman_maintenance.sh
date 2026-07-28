#!/usr/bin/env bash
#
# Run pg_partman's maintenance procedure against a running pagila
# database: creates any new partitions the payment table needs (keeping
# p_premake months pre-created, per pg_partman-setup.sql) and runs
# retention/other housekeeping. pg_partman's own background worker
# (pg_partman_bgw) is intentionally not used here -- this project runs
# maintenance from an external cron job instead, so it doesn't depend on
# shared_preload_libraries or a long-lived worker process inside the
# container.
#
# Connection is taken from the standard PG* environment variables /
# ~/.pgpass, same as psql:
#   PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE, PGSSLMODE, ...
#
# Usage:
#   ./scripts/run_partman_maintenance.sh
#
# Example crontab entry (runs daily at 02:00):
#   0 2 * * * PGHOST=localhost PGUSER=postgres PGPASSWORD=secret PGDATABASE=pagila \
#     /path/to/pagila/scripts/run_partman_maintenance.sh >> /var/log/pagila-partman.log 2>&1

set -euo pipefail

: "${PGHOST:=localhost}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGDATABASE:=pagila}"
export PGHOST PGPORT PGUSER PGDATABASE

echo "Running pg_partman maintenance on ${PGDATABASE} at ${PGHOST}:${PGPORT}..."

psql -v ON_ERROR_STOP=1 -c "CALL partman.run_maintenance_proc(0, true, true);"

echo "Done."
