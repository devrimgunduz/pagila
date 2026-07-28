#!/usr/bin/env bash
#
# Populate one month of rental/payment activity into a running pagila
# database, creating that month's payment partition if it doesn't exist
# yet. Meant to be scheduled (cron, CI cron job, etc.) to run once a
# month, but safe to run by hand.
#
# Connection is taken from the standard PG* environment variables /
# ~/.pgpass, same as psql:
#   PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE, PGSSLMODE, ...
#
# Usage:
#   ./scripts/add_monthly_data.sh            # populate the current month
#   ./scripts/add_monthly_data.sh 2026-08    # populate a specific month
#
# Example crontab entry (runs at 03:00 on the 1st of every month):
#   0 3 1 * * PGHOST=localhost PGUSER=postgres PGPASSWORD=secret PGDATABASE=pagila \
#     /path/to/pagila/scripts/add_monthly_data.sh >> /var/log/pagila-monthly.log 2>&1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${PGHOST:=localhost}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGDATABASE:=pagila}"
export PGHOST PGPORT PGUSER PGDATABASE

TARGET_MONTH="${1:-$(date +%Y-%m)}"

if ! [[ "$TARGET_MONTH" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
  echo "usage: $(basename "$0") [YYYY-MM]" >&2
  exit 1
fi

echo "Populating ${PGDATABASE} on ${PGHOST}:${PGPORT} with a month of rental/payment activity for ${TARGET_MONTH}..."

psql -v ON_ERROR_STOP=1 -v target_month="${TARGET_MONTH}-01" \
  -f "${SCRIPT_DIR}/add_monthly_data.sql"

echo "Done."
