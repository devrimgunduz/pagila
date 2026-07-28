-- Populate one month of realistic rental/payment activity in an existing
-- pagila database, creating that month's payment partition first if needed.
--
-- Not meant to be run directly with `psql -f` alone: it expects a
-- `target_month` variable (first day of the month, e.g. 2026-08-01), which
-- scripts/add_monthly_data.sh sets for you. Safe to invoke by hand too:
--
--   psql -d pagila -v target_month=2026-08-01 -f scripts/add_monthly_data.sql
--
-- Re-running for a month that already has a partition is fine (the
-- partition step is skipped); re-running the data step just appends
-- another batch of activity for that month.

\set ON_ERROR_STOP on

\if :{?target_month}
\else
  \echo 'ERROR: target_month not set. Pass -v target_month=YYYY-MM-01 (see add_monthly_data.sh).'
  \quit 1
\endif

BEGIN;

-- 1. Create the month's payment partition if it doesn't exist yet.
--    (Not a DO block: psql's :'var' interpolation is intentionally skipped
--    inside $$...$$ bodies, so the partition name/bounds are worked out
--    with plain SELECT ... \gset and \if instead.)
SELECT
  :'target_month'::date AS month_start,
  (:'target_month'::date + interval '1 month')::date AS month_end,
  format('payment_p%s', to_char(:'target_month'::date, 'YYYY_MM')) AS part_name,
  CASE WHEN :'target_month'::date <> date_trunc('month', :'target_month'::date)::date
       THEN 'true' ELSE 'false' END AS bad_month
\gset

\if :bad_month
  \echo 'ERROR: target_month must be the first day of a month, got' :target_month
  \quit 1
\endif

SELECT CASE WHEN EXISTS (
    SELECT 1 FROM pg_class WHERE relname = :'part_name' AND relkind = 'r'
  ) THEN 'true' ELSE 'false' END AS part_exists
\gset

\if :part_exists
  \echo 'Partition' :part_name 'already exists, skipping create'
\else
  CREATE TABLE public.:"part_name" PARTITION OF public.payment
    FOR VALUES FROM (:'month_start') TO (:'month_end');
  \echo 'Created partition' :part_name
\endif

-- 2. Generate a batch of new rentals (and matching payments) dated within
--    the target month. Everything is clamped so it never lands after
--    "now" (can't rent something in the future) or after the month's end
--    (so payments always land in the partition just created above).
WITH bounds AS (
  SELECT
    :'target_month'::date AS month_start,
    LEAST(
      (:'target_month'::date + interval '1 month')::timestamptz - interval '1 second',
      now()
    ) AS upper_bound
),
days AS (
  SELECT
    b.upper_bound,
    d::date AS day,
    (15 + floor(random() * 21))::int AS n
  FROM bounds b,
       generate_series(b.month_start, LEAST((b.month_start + interval '1 month' - interval '1 day')::date, b.upper_bound::date), interval '1 day') d
),
expanded AS (
  SELECT upper_bound, day FROM days, generate_series(1, n)
),
rental_rows AS (
  SELECT
    upper_bound,
    LEAST(day::timestamptz + (random() * interval '1 day'), upper_bound) AS rental_date,
    (SELECT inventory_id FROM inventory ORDER BY random() LIMIT 1) AS inventory_id,
    (SELECT customer_id FROM customer WHERE create_date <= day ORDER BY random() LIMIT 1) AS customer_id,
    (CASE WHEN random() < 0.5 THEN 1 ELSE 2 END) AS staff_id
  FROM expanded
),
eligible_rows AS (
  SELECT * FROM rental_rows WHERE customer_id IS NOT NULL
),
inserted_rentals AS (
  INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id, return_date, last_update)
  SELECT
    er.rental_date,
    er.inventory_id,
    er.customer_id,
    er.staff_id,
    CASE
      WHEN er.rental_date > (er.upper_bound - interval '14 days') AND random() < 0.15
        THEN NULL
      ELSE LEAST(
        er.rental_date + ((f.rental_duration * (0.6 + random() * 0.9)) || ' days')::interval,
        er.upper_bound
      )
    END,
    LEAST(er.rental_date + interval '1 hour', er.upper_bound)
  FROM eligible_rows er
  JOIN inventory i ON i.inventory_id = er.inventory_id
  JOIN film f ON f.film_id = i.film_id
  RETURNING rental_id, customer_id, staff_id, rental_date, return_date, inventory_id
)
INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT
  ir.customer_id,
  ir.staff_id,
  ir.rental_id,
  f.rental_rate,
  LEAST(
    COALESCE(ir.return_date, ir.rental_date + interval '1 day' + (random() * interval '2 days')),
    (SELECT upper_bound FROM bounds)
  )
FROM inserted_rentals ir
JOIN inventory i ON i.inventory_id = ir.inventory_id
JOIN film f ON f.film_id = i.film_id
WHERE random() < 0.98;

COMMIT;

-- Summary for the log.
SELECT
  :'target_month' AS target_month,
  count(*) FILTER (WHERE rental_date >= :'target_month'::date
                     AND rental_date <  (:'target_month'::date + interval '1 month')) AS rentals_in_month
FROM rental;
