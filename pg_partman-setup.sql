-- Hand future maintenance of the payment table's monthly partitions over
-- to pg_partman, instead of adding them by hand (see scripts/add_monthly_data.sh
-- for how that used to work).
--
-- pagila-schema.sql already ships payment partitions through 2026-07,
-- manually created before pg_partman was introduced. create_parent() is
-- told to only start managing partitions from 2026-08 onward, so it
-- leaves that existing history alone and just keeps premake (4, the
-- default) months of future partitions pre-created from then on --
-- pg_partman's own background worker (pg_partman_bgw) is intentionally
-- not used for this; see scripts/run_partman_maintenance.sh, meant to be
-- scheduled via cron instead.
--
-- If you're loading this against a payment table whose manually-created
-- partitions extend further than 2026-07, bump p_start_partition below to
-- match, so pg_partman doesn't try to create a partition that overlaps
-- one you already have.

CREATE SCHEMA IF NOT EXISTS partman;
CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman;

SELECT partman.create_parent(
    p_parent_table   := 'public.payment',
    p_control        := 'payment_date',
    p_interval       := '1 month',
    p_type           := 'range',
    p_start_partition := '2026-08-01 00:00:00+00'
);
