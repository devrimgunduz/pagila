# Pagila

Pagila started as a port of the [Sakila](https://dev.mysql.com/doc/sakila/en/) example database available for MySQL, which was
originally developed by Mike Hillyer of the MySQL AB documentation team. It
is intended to provide a standard schema that can be used for examples in
books, tutorials, articles, samples, etc.

Pagila has been tested against PostgreSQL 18 and above.

All the tables, data, views, and functions have been ported; some of the
changes made were:

- Changed char(1) true/false fields to true boolean fields
- The last_update columns were set with triggers to update them
- Added foreign keys
- Removed 'DEFAULT 0' on foreign keys since it's pointless with real FK's
- Used PostgreSQL built-in fulltext searching for fulltext index.
  Removed the need for the film_text table.
- The rewards_report function was ported to a simple SRF
- Added JSONB data

The pagila database is made available under PostgreSQL license.

## EXAMPLE QUERY

Find late rentals:

```sql
SELECT
	CONCAT(customer.last_name, ', ', customer.first_name) AS customer,
	address.phone,
	film.title
FROM
	rental
	INNER JOIN customer ON rental.customer_id = customer.customer_id
	INNER JOIN address ON customer.address_id = address.address_id
	INNER JOIN inventory ON rental.inventory_id = inventory.inventory_id
	INNER JOIN film ON inventory.film_id = film.film_id
WHERE
	rental.return_date IS NULL
	AND rental_date < CURRENT_DATE
ORDER BY
	title
LIMIT 5;
```

## FULLTEXT SEARCH

Fulltext functionality is built in PostgreSQL, so parts of the schema exist
in the main schema file.

Example usage:

SELECT * FROM film WHERE fulltext @@ to_tsquery('fate&india');

pgAdmin is included in the docker-compose.

Navigate to the URL : http://localhost:5050/
Default Username: admin@admin.com
Default Password: root

## JSONB

`actor_info` is a view within the DVD rental domain itself: for each actor,
it aggregates their films into a JSONB object keyed by category, e.g.
`{"Games": ["ACADEMY DINOSAUR", "WEDDING APOLLO"], "Drama": [...], ...}`.
It's a good place to get familiar with JSONB's operators:

```sql
SELECT actor_id, first_name, last_name, film_info -> 'Games' AS games
FROM actor_info
WHERE film_info -> 'Games' ? 'ACADEMY DINOSAUR';
```

`pagila-schema-jsonb.sql` / `pagila-data-yum-jsonb.backup` /
`pagila-data-apt-jsonb.backup` are a separate, unrelated JSONB example: two
tables holding real package metadata from apt.postgresql.org and
yum.postgresql.org, useful for practicing JSONB on a different shape of
data. See the INSTALL NOTE below for how to load them.

## SQL/JSON FUNCTIONS (PostgreSQL 17+)

PostgreSQL 17 added the SQL-standard SQL/JSON query functions
(`JSON_EXISTS()`, `JSON_VALUE()`, `JSON_QUERY()`), the constructor functions
(`JSON()`, `JSON_SCALAR()`, `JSON_SERIALIZE()`), and `JSON_TABLE()`.
`actor_info.film_info` (see JSONB above) is a convenient place to try them
out; all of the queries below were run against it.

`JSON_EXISTS()` checks whether a path matches anything, without pulling the
data back:

```sql
SELECT actor_id, first_name, last_name
FROM actor_info
WHERE JSON_EXISTS(film_info, '$.Games');
```

`JSON_VALUE()` pulls out a single scalar, `JSON_QUERY()` pulls out an
object/array:

```sql
SELECT actor_id, first_name, last_name,
       JSON_VALUE(film_info, '$.Games[0]') AS first_game_film,
       JSON_QUERY(film_info, '$.Games') AS games_films
FROM actor_info
WHERE JSON_EXISTS(film_info, '$.Games');
```

`JSON_TABLE()` turns JSON into rows. On its own it replaces a
`jsonb_array_elements()` call:

```sql
SELECT jt.*
FROM actor_info,
     JSON_TABLE(film_info, '$.Games[*]' COLUMNS (
       ord FOR ORDINALITY,
       game_title text PATH '$'
     )) AS jt
WHERE actor_id = 1;
```

`NESTED PATH` is where it earns its keep: flattening every category for an
actor into (category, title) rows in one query, no `jsonb_each()` +
`jsonb_array_elements()` combo needed:

```sql
WITH doc AS (
  SELECT jsonb_build_object(
    'actor', first_name || ' ' || last_name,
    'categories', (
      SELECT jsonb_agg(jsonb_build_object('category', key, 'titles', value))
      FROM jsonb_each(film_info)
    )
  ) AS payload
  FROM actor_info
  WHERE actor_id = 1
)
SELECT jt.*
FROM doc,
     JSON_TABLE(
       payload, '$'
       COLUMNS (
         actor text PATH '$.actor',
         NESTED PATH '$.categories[*]' COLUMNS (
           category text PATH '$.category',
           NESTED PATH '$.titles[*]' COLUMNS (
             title text PATH '$'
           )
         )
       )
     ) AS jt
ORDER BY category, title;
```

The constructor functions build or validate JSON rather than query it:

```sql
-- JSON_SCALAR(): wrap a plain SQL value as a JSON scalar
SELECT title, JSON_SCALAR(title) AS title_scalar, JSON_SCALAR(rental_rate) AS rate_scalar
FROM film
ORDER BY film_id
LIMIT 3;

-- JSON_SERIALIZE(): render JSON/JSONB back out as text
SELECT actor_id, JSON_SERIALIZE(film_info::json RETURNING text) AS film_info_text
FROM actor_info
WHERE actor_id = 1;

-- JSON(): parse/validate a text payload as JSON, optionally rejecting duplicate keys
SELECT JSON('{"actor_id": 1, "note": "top renter"}') AS parsed;
SELECT JSON('{"a": 1, "a": 2}' WITH UNIQUE KEYS) AS parsed; -- ERROR: duplicate JSON object key value
```

Note: as tested against 17.10/18.4/19beta2, `JSON_SERIALIZE()` mishandles a
`jsonb`-typed argument passed directly (silently returns 1 byte of
garbage) — casting to `json` first, as above, avoids it.

## PGVECTOR

`pgvector` isn't bundled with PostgreSQL — `docker-compose.yml` installs it
from the PGDG apt repo (alongside pg_partman, see "PARTITIONING WITH
PG_PARTMAN" below) via the `Dockerfile`, and `pagila-schema.sql` runs
`CREATE EXTENSION vector`.

`film_embedding` gives each film a `vector(20)` in a shape meant to be
inspected, not just queried: dimensions 1-16 are a multi-hot encoding of the
film's categories (`film_category` can hold more than one per film), and
17-20 are `length`, `rental_rate`, `replacement_cost`, and `rental_duration`,
each min-max normalized to `[0, 1]`. These aren't real text embeddings from a
language model — there's no plot-summary model in this dataset to run — but
engineered from data already in `film`, so nearest-neighbor search returns
films that actually share categories and attributes, which makes the results
easy to sanity-check by eye:

```sql
SELECT f.film_id, f.title, fe.embedding
FROM film_embedding fe JOIN film f USING (film_id)
WHERE f.film_id = 1;
```

pgvector adds three distance operators: `<->` (Euclidean/L2), `<#>` (negative
inner product), and `<=>` (cosine distance). Cosine is the natural fit here,
since it ignores the vectors' magnitude and only compares direction — so a
short, cheap film and a long, expensive one in the same categories can still
land close together:

```sql
-- the 5 films most similar to ACADEMY DINOSAUR (Games, New, Travel):
SELECT f2.film_id, f2.title,
       fe1.embedding <=> fe2.embedding AS distance
FROM film_embedding fe1
JOIN film_embedding fe2 ON fe2.film_id <> fe1.film_id
JOIN film f2 ON f2.film_id = fe2.film_id
WHERE fe1.film_id = 1
ORDER BY distance
LIMIT 5;
```

`pagila-schema.sql` creates an HNSW index (`film_embedding_embedding_hnsw_idx`)
on `embedding` using `vector_cosine_ops`, matching the `<=>` operator above —
an ANN index has to be built for the specific operator/distance it'll be
queried with:

```sql
-- confirm the planner is using the HNSW index rather than a sequential scan:
EXPLAIN SELECT film_id, title
FROM film_embedding fe JOIN film USING (film_id)
ORDER BY embedding <=> (SELECT embedding FROM film_embedding WHERE film_id = 1)
LIMIT 5;
```

HNSW (unlike ivfflat) needs no training step at `CREATE INDEX` time, which is
why it was picked here: `pagila-schema.sql` creates the index before any data
exists (`pagila-data.sql`/`pagila-insert-data.sql` load afterward), and an
ivfflat index built against zero rows would cluster poorly.

## UUIDV7 (PostgreSQL 18+)

PostgreSQL 18 added built-in UUID generation: `uuidv7()` (time-ordered,
per [the docs](https://www.postgresql.org/docs/18/functions-uuid.html#FUNC_UUID_GEN_TABLE))
and `uuidv4()` (the old fully-random kind), plus `uuid_extract_timestamp()`
and `uuid_extract_version()` to inspect an existing UUID.

`customer`, `rental`, and `payment` each have a `uuid` column
(`DEFAULT uuidv7()`, unique-indexed) alongside their normal integer primary
key — a realistic pattern for exposing a non-guessable, sortable ID
externally (e.g. in an API) without leaking the sequential internal one:

```sql
SELECT customer_id, uuid, uuid_extract_timestamp(uuid) AS created_at
FROM customer
ORDER BY customer_id
LIMIT 3;

-- uuidv7 values sort by creation time, so this is equivalent to
-- "the 3 most recently created customers":
SELECT customer_id, first_name, last_name
FROM customer
ORDER BY uuid DESC
LIMIT 3;
```

Note: "creation time" here means when each row was generated by this
project's data-loading scripts, not the fictional `create_date`/
`rental_date` columns — `uuidv7()` embeds real wall-clock time, so ordering
by `uuid` tracks insertion order, not the sample data's backdated business
timestamps.

## VIRTUAL GENERATED COLUMNS (PostgreSQL 18+)

Generated columns (`GENERATED ALWAYS AS (...)`) existed before PostgreSQL 18,
but only as `STORED` — computed on write and persisted like a normal column.
18 added the `VIRTUAL` kind (and made it the default when `STORED` is
omitted): computed on read instead, like a view expression, so it adds no
storage and never goes stale relative to the columns it depends on.

`film.length_hours` is `VIRTUAL`, derived from the existing `length` column
(minutes) rather than adding new data:

```sql
SELECT film_id, title, length, length_hours
FROM film
ORDER BY film_id
LIMIT 3;
```

Note: unlike `STORED` generated columns, `VIRTUAL` ones can't be indexed
directly (`CREATE INDEX ... (length_hours)` fails with "indexes on virtual
generated columns are not supported") — index the underlying expression
instead (`CREATE INDEX ON film (round(length / 60.0, 2))`) if you need one.

## PARTITIONED TABLES

The payment table is designed as a partitioned table, with one partition per
calendar month. `pagila-schema.sql` ships partitions covering January 2022
through July 2026, created by hand. From August 2026 onward, partitions are
created automatically by pg_partman instead — see "PARTITIONING WITH
PG_PARTMAN" below.

## PARTITIONING WITH PG_PARTMAN

The `docker-compose.yml` setup builds a custom image (see `Dockerfile`)
that adds [pg_partman](https://github.com/pgpartman/pg_partman) to
`postgres:18` from the PGDG apt repo, and hands the `payment` table's
future partitions over to it (`pg_partman-setup.sql`) instead of creating
them by hand. It's a good way to see pg_partman adopt an existing
native-partitioned table without disturbing the partitions that already
exist:

```sql
-- how it's configured:
SELECT partman.create_parent(
    p_parent_table    := 'public.payment',
    p_control         := 'payment_date',
    p_interval        := '1 month',
    p_type            := 'range',
    p_start_partition := '2026-08-01 00:00:00+00'
);
```

`p_start_partition` is the key part: it tells pg_partman to only manage
partitions from August 2026 onward, leaving the hand-created 2022-2026
history alone. From then on, `p_premake` (default 4) months are kept
pre-created automatically — no more manual `CREATE TABLE ... PARTITION OF`
— but *only* if maintenance actually runs regularly. This project
intentionally doesn't use pg_partman's own background worker
(`pg_partman_bgw`) for that, to avoid the extra `shared_preload_libraries`
dependency and long-lived worker process inside the container; instead,
`scripts/run_partman_maintenance.sh` runs the maintenance call and is
meant to be scheduled via cron, the same way `scripts/add_monthly_data.sh`
is (see "KEEPING DATA FRESH" below):

```sql
-- see its config:
SELECT parent_table, control, partition_interval, premake
FROM partman.part_config;

-- list all of payment's partitions, old (hand-created) and new (pg_partman):
SELECT * FROM partman.show_partitions('public.payment');

-- what scripts/run_partman_maintenance.sh calls: create any partitions
-- that are due, ANALYZE them, and log to pg_jobmon if it's installed:
CALL partman.run_maintenance_proc(0, true, true);
```

```
# Example crontab entry, running daily at 02:00:
0 2 * * * PGHOST=localhost PGUSER=postgres PGPASSWORD=secret PGDATABASE=pagila \
  /path/to/pagila/scripts/run_partman_maintenance.sh >> /var/log/pagila-partman.log 2>&1
```

## SQL/PGQ - PROPERTY GRAPH QUERIES (PostgreSQL 19+)

PostgreSQL 19 adds `CREATE PROPERTY GRAPH` and `GRAPH_TABLE`, an
implementation of SQL/PGQ (ISO/IEC 9075-16), the SQL-standard way to run
graph pattern-matching queries. A property graph is a read-only view over
existing relational tables — nothing is duplicated — so it declares which
tables act as graph vertices and which act as edges, and the planner
rewrites `MATCH` patterns into ordinary joins underneath (`EXPLAIN` shows
plain `Nested Loop`/`Index Scan` nodes, not a special graph executor node).

Because this needs PostgreSQL 19, which is newer than this project's
`postgres:18`-based `docker-compose.yml`, it isn't wired into the compose
pipeline; instead, `pagila-sql-pgq-setup.sql` is a standalone script to run by
hand, after `pagila-schema.sql`/`pagila-data.sql`, against a PostgreSQL 19+
instance:

```sql
CREATE PROPERTY GRAPH pagila_graph
  VERTEX TABLES (
    actor    KEY (actor_id)    LABEL actor    PROPERTIES (actor_id, first_name, last_name),
    film     KEY (film_id)     LABEL film     PROPERTIES (film_id, title, release_year, rating),
    category KEY (category_id) LABEL category PROPERTIES (category_id, name)
  )
  EDGE TABLES (
    film_actor
      SOURCE KEY (actor_id) REFERENCES actor (actor_id)
      DESTINATION KEY (film_id) REFERENCES film (film_id)
      LABEL acted_in NO PROPERTIES,
    film_category
      SOURCE KEY (film_id) REFERENCES film (film_id)
      DESTINATION KEY (category_id) REFERENCES category (category_id)
      LABEL categorized_as NO PROPERTIES
  );
```

`film_actor` and `film_category` work as edge tables as-is, with no changes
needed — both are already primary-keyed on exactly the (source,
destination) column pair a graph edge needs. `\d pagila_graph` describes
the shape:

```
 Element Alias |    Element Table     | Element Kind | Source Vertex Alias | Destination Vertex Alias
---------------+----------------------+--------------+---------------------+--------------------------
 actor         | public.actor         | vertex       |                     |
 category      | public.category      | vertex       |                     |
 film          | public.film          | vertex       |                     |
 film_actor    | public.film_actor    | edge         | actor               | film
 film_category | public.film_category | edge         | film                | category
```

A one-hop pattern — every film PENELOPE GUINESS acted in:

```sql
SELECT title
FROM GRAPH_TABLE (pagila_graph
  MATCH (a IS actor WHERE a.first_name = 'PENELOPE' AND a.last_name = 'GUINESS')-[IS acted_in]->(f IS film)
  COLUMNS (f.title)
)
ORDER BY title;
```

A two-hop pattern through `film` and back out through `acted_in` in
reverse (`<-[IS acted_in]-`) finds her co-stars. Filters that compare two
pattern variables (`a1.actor_id <> a2.actor_id`) aren't supported inside
the pattern itself in this initial implementation, so that comparison
moves to the outer query instead:

```sql
SELECT first_name, last_name, title
FROM GRAPH_TABLE (pagila_graph
  MATCH (a1 IS actor WHERE a1.first_name = 'PENELOPE' AND a1.last_name = 'GUINESS')
        -[IS acted_in]->(f IS film)<-[IS acted_in]-(a2 IS actor)
  COLUMNS (a1.actor_id AS a1_id, a2.actor_id AS a2_id, a2.first_name, a2.last_name, f.title)
)
WHERE a1_id <> a2_id
ORDER BY last_name, first_name, title;
```

Chaining through both edge tables (`acted_in` then `categorized_as`) reaches
a second vertex type in one pattern — every category she's appeared in:

```sql
SELECT DISTINCT name
FROM GRAPH_TABLE (pagila_graph
  MATCH (a IS actor WHERE a.first_name = 'PENELOPE' AND a.last_name = 'GUINESS')
        -[IS acted_in]->(f IS film)-[IS categorized_as]->(c IS category)
  COLUMNS (c.name AS name)
)
ORDER BY name;
```

A 4-hop pattern (`actor -> film -> category <- film <- actor`) plus a
`co_stars` query, combined with `NOT IN`, recommends actors who share a
genre with her but have never actually shared a film:

```sql
WITH genre_mates AS (
  SELECT DISTINCT a2_id, first_name, last_name
  FROM GRAPH_TABLE (pagila_graph
    MATCH (a1 IS actor WHERE a1.first_name = 'PENELOPE' AND a1.last_name = 'GUINESS')
          -[IS acted_in]->(f1 IS film)-[IS categorized_as]->(c IS category)
          <-[IS categorized_as]-(f2 IS film)<-[IS acted_in]-(a2 IS actor)
    COLUMNS (a1.actor_id AS a1_id, a2.actor_id AS a2_id, a2.first_name, a2.last_name)
  )
  WHERE a1_id <> a2_id
),
co_stars AS (
  SELECT DISTINCT a2_id
  FROM GRAPH_TABLE (pagila_graph
    MATCH (a1 IS actor WHERE a1.first_name = 'PENELOPE' AND a1.last_name = 'GUINESS')
          -[IS acted_in]->(f IS film)<-[IS acted_in]-(a2 IS actor)
    COLUMNS (a2.actor_id AS a2_id)
  )
)
SELECT first_name, last_name
FROM genre_mates
WHERE a2_id NOT IN (SELECT a2_id FROM co_stars)
ORDER BY last_name, first_name;
```

Note: this initial PostgreSQL 19 implementation covers fixed-depth
patterns only — quantified/variable-length path patterns (e.g. a `{1,3}`
hop-count range) and path search modes (`ANY SHORTEST`, `ALL`) aren't
supported yet, which is why the "genre mates" query above chains two fixed
patterns with `NOT IN` rather than expressing it as a single variable-length
path.

## TEMPORAL TABLES (PostgreSQL 19+)

PostgreSQL 19 adds application-time temporal support from SQL:2011
(ISO/IEC 9075-2): `WITHOUT OVERLAPS` primary/unique keys and temporal
foreign keys built on range-typed columns, plus native `UPDATE`/`DELETE
... FOR PORTION OF` DML that splits a row at the edges of the portion
being changed instead of requiring hand-written split logic. Like SQL/PGQ
above, this needs PostgreSQL 19, so it isn't wired into
`docker-compose.yml`; `pagila-temporal-setup.sql` is a standalone script
to run by hand, after `pagila-schema.sql`/`pagila-data.sql`, against a
PostgreSQL 19+ instance.

`film_price_history` tracks `film.rental_rate`/`replacement_cost` as
they've actually changed over a title's life, one row per validity
period. `WITHOUT OVERLAPS` is implemented as a GiST exclusion constraint
under the hood, so it needs the `btree_gist` extension for a
GiST-compatible equality operator class on the non-range key column
(`film_id`):

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE film_price_history (
    film_id integer NOT NULL REFERENCES film (film_id),
    rental_rate numeric(4,2) NOT NULL,
    replacement_cost numeric(5,2) NOT NULL,
    valid_at daterange NOT NULL,
    PRIMARY KEY (film_id, valid_at WITHOUT OVERLAPS)
);
```

`store_film_price_override` layers a per-store rate on top for some
sub-period. Its `FOREIGN KEY (film_id, PERIOD valid_at)` is a *temporal*
foreign key: it requires every override period to fall entirely within a
period where `film_price_history` actually has that film on record — not
merely overlap it:

```sql
CREATE TABLE store_film_price_override (
    store_id integer NOT NULL REFERENCES store (store_id),
    film_id integer NOT NULL,
    rental_rate numeric(4,2) NOT NULL,
    valid_at daterange NOT NULL,
    PRIMARY KEY (store_id, film_id, valid_at WITHOUT OVERLAPS),
    FOREIGN KEY (film_id, PERIOD valid_at) REFERENCES film_price_history (film_id, PERIOD valid_at)
);
```

`pagila-temporal-setup.sql` populates ACADEMY DINOSAUR (`film_id` 1) with
three non-overlapping periods — a new-release price, a mid-life discount,
and its current `0.99`/`20.99` — and gives ACE GOLDFINGER (`film_id` 2) a
single open-ended period at its current price. `WITHOUT OVERLAPS` is
scoped to `film_id`, so two different films can have periods that overlap
the same calendar dates without conflict:

```sql
SELECT film_id, rental_rate, replacement_cost, valid_at
FROM film_price_history
ORDER BY film_id, valid_at;
```

```
 film_id | rental_rate | replacement_cost |        valid_at
---------+-------------+-------------------+-------------------------
       1 |        4.99 |             24.99 | [2022-01-01,2023-01-01)
       1 |        2.99 |             22.99 | [2023-01-01,2024-06-01)
       1 |        0.99 |             20.99 | [2024-06-01,2024-07-01)
       1 |        0.49 |             20.99 | [2024-07-01,2024-08-01)
       1 |        0.99 |             20.99 | [2024-08-01,)
       2 |        4.99 |             12.99 | [2023-01-01,2023-06-01)
       2 |        4.99 |             12.99 | [2023-07-01,)
```

(The two-row split for each film above is what's left after the
`FOR PORTION OF` examples below run — see there for the before/after.)

**Overlaps predicate (`&&`)**: every price period, for any film, in effect
at any point during a given window — the summer of 2024:

```sql
SELECT film_id, rental_rate, valid_at
FROM film_price_history
WHERE valid_at && daterange('2024-06-15', '2024-07-15')
ORDER BY film_id, valid_at;
```

**Containment predicate (`@>`)**: the rate in effect on one specific date
— what ACADEMY DINOSAUR rented for on 2023-05-15:

```sql
SELECT rental_rate
FROM film_price_history
WHERE film_id = 1 AND valid_at @> DATE '2023-05-15';
-- 2.99
```

**`UPDATE ... FOR PORTION OF`**: a one-month summer promotion cuts
ACADEMY DINOSAUR's rate to `0.49`, but only for July 2024. Before this
runs, the row is a single open-ended period at `0.99` starting
2024-06-01; `FOR PORTION OF` splits it into three, leaving the parts
outside the given range untouched:

```sql
UPDATE film_price_history
FOR PORTION OF valid_at FROM '2024-07-01' TO '2024-08-01'
SET rental_rate = 0.49
WHERE film_id = 1;
```

```
 film_id | rental_rate |        valid_at
---------+-------------+-------------------------
       1 |        0.99 | [2024-06-01,2024-07-01)   <- untouched, before
       1 |        0.49 | [2024-07-01,2024-08-01)   <- the portion, updated
       1 |        0.99 | [2024-08-01,)              <- untouched, after (still open-ended)
```

A plain `UPDATE ... WHERE valid_at && ...` would instead overwrite the
*entire* matching row's `rental_rate`, wiping out the price for all of
June through the present — `FOR PORTION OF` is what makes "just July"
possible without hand-writing the two boundary INSERTs yourself.

**`DELETE ... FOR PORTION OF`** works the same way. ACE GOLDFINGER is
pulled from the catalog for June 2023, splitting its single open-ended
row into a bounded one and a new open-ended one, opening a gap where the
film has no price on record at all:

```sql
DELETE FROM film_price_history
FOR PORTION OF valid_at FROM '2023-06-01' TO '2023-07-01'
WHERE film_id = 2;
```

```
 film_id | rental_rate |        valid_at
---------+-------------+-------------------------
       2 |        4.99 | [2023-01-01,2023-06-01)
       2 |        4.99 | [2023-07-01,)
```

Note: `FOR PORTION OF` still enforces the temporal foreign key. Store 2's
override runs `[2024-06-01,)`, referencing ACADEMY DINOSAUR's
`[2024-06-01,2024-07-01)`/`[2024-07-01,2024-08-01)` periods created by the
`UPDATE` above; trying to delete either one out from under it fails just
like a non-temporal FK would:

```sql
DELETE FROM film_price_history
FOR PORTION OF valid_at FROM '2024-07-25' TO '2024-08-01'
WHERE film_id = 1;
-- ERROR:  update or delete on table "film_price_history" violates foreign key
--         constraint "store_film_price_override_film_id_valid_at_fkey" on table
--         "store_film_price_override"
```

Joining the two tables on overlapping periods compares each store's
override rate against the base rate it was active during, using `*` to
compute the overlap itself as a range:

```sql
SELECT o.store_id, o.film_id, o.rental_rate AS store_rate,
       h.rental_rate AS base_rate, o.valid_at * h.valid_at AS overlap_period
FROM store_film_price_override o
JOIN film_price_history h ON o.film_id = h.film_id AND o.valid_at && h.valid_at
ORDER BY o.store_id;
```

## KEEPING DATA FRESH

`scripts/add_monthly_data.sh` populates one calendar month of new,
realistic rental/payment activity into a running pagila database. It's
meant to be run once a month (e.g. via cron) against a long-lived pagila
instance so the data keeps looking current instead of going stale.

```
# Populate the current month (uses the standard PG* env vars / ~/.pgpass
# for the connection, same as psql):
PGHOST=localhost PGUSER=postgres PGPASSWORD=secret PGDATABASE=pagila \
  ./scripts/add_monthly_data.sh

# Populate a specific month instead:
./scripts/add_monthly_data.sh 2026-08
```

Example crontab entry, running at 03:00 on the 1st of every month:

```
0 3 1 * * PGHOST=localhost PGUSER=postgres PGPASSWORD=secret PGDATABASE=pagila \
  /path/to/pagila/scripts/add_monthly_data.sh >> /var/log/pagila-monthly.log 2>&1
```

It's safe to re-run for the same month: it just appends another batch of
activity for that month.

## INSTALL NOTE

The pagila-data.sql file and the pagila-insert-data.sql both contain the same
data, the former using COPY commands, the latter using INSERT commands, so you
only need to install one of them. Both formats are provided for those who have
trouble using one version or another, and for instructors who want to point out
the longer data loading time with the latter. You can load them via psql, pgAdmin, etc.

Since JSONB data is quite large to store on Github, the backup is not a plain SQL
file. You can still use psql/pgAdmin, etc. to load `pagila-schema-jsonb.backup`, however
please use pg_restore to load jsonb data files:

```
pg_restore /usr/share/pagila/pagila-data-yum-jsonb.backup -U postgres -d pagila
pg_restore /usr/share/pagila/pagila-data-apt-jsonb.backup -U postgres -d pagila
```

## VERSION HISTORY

Version 4.1.0
- Add pgvector support and a `film_embedding` table with a `vector(20)` per film — a multi-hot encoding of its categories plus a few normalized numeric attributes, engineered from existing `film`/`film_category` data rather than a real text-embedding model — indexed with HNSW (`vector_cosine_ops`) and documented in the README with cosine-distance nearest-neighbor examples
- Install `pg_partman` and `pgvector` in the `Dockerfile` from the PGDG apt repo instead of building both from source, now that the repo carries current packages for each
- Add `pagila-sql-pgq-setup.sql`, declaring a `pagila_graph` property graph over the existing `actor`/`film`/`category` vertex tables and `film_actor`/`film_category` edge tables (no new data), demonstrating PostgreSQL 19's SQL/PGQ (`CREATE PROPERTY GRAPH`/`GRAPH_TABLE`) with `MATCH` pattern examples in the README, verified against a `postgres:19beta2` container, with a matching panel added to `pagila-schema-diagram.png`
- Add `film.length_hours`, a `VIRTUAL` generated column (`round(length / 60.0, 2)`) demonstrating PostgreSQL 18's new virtual generated columns, documented in the README alongside a note that (unlike `STORED`) virtual generated columns can't be indexed directly
- Add `pagila-temporal-setup.sql`, declaring `film_price_history` (`WITHOUT OVERLAPS` primary key on `film_id`/a `daterange`) and `store_film_price_override` (a temporal foreign key back to it), demonstrating PostgreSQL 19's SQL:2011 application-time temporal support — `WITHOUT OVERLAPS` keys, temporal foreign keys, and `UPDATE`/`DELETE ... FOR PORTION OF` row-splitting DML — with overlaps/containment predicate examples in the README, verified against a `postgres:19beta2` container, with a matching panel added to `pagila-schema-diagram.png`

Version 4.0.0

- Refresh `pagila-data.sql` with more diverse, less repetitive sample data:
  - Grow the customer base from 599 to 999, with signups spread across 2022-2026 instead of a single date
  - Grow rental activity from ~16k to ~51.8k rows, and payments from ~16k to ~51k rows, spanning January 2022 through July 2026 instead of a few months in 2022
  - Randomize `last_update`/`create_date` timestamps across all tables instead of reusing one fixed value per table
- Add 48 new monthly partitions to the `payment` table in `pagila-schema.sql` (Aug 2022 - Jul 2026) to support the extended date range
- Add `scripts/add_monthly_data.sh` to keep a running pagila instance current: creates the next `payment` partition and populates a month of new rental/payment activity, meant to be scheduled monthly
- Rework the `actor_info` view to return a JSONB column (film titles grouped by category) instead of a concatenated text string, so it's a domain-relevant example for practicing JSONB operators (fixes #21)
- Change `language.name` from `character(20)` to `text`, and strip the trailing blank-padding it left in the shipped data, matching the `text`-everywhere convention used by every other column (fixes #33)
- Document PostgreSQL 17's SQL/JSON query functions (`JSON_EXISTS()`, `JSON_VALUE()`, `JSON_QUERY()`), `JSON_TABLE()`, and the constructor functions (`JSON()`, `JSON_SCALAR()`, `JSON_SERIALIZE()`) in the README, with example queries verified against `actor_info`
- Raise the minimum supported PostgreSQL version to 18
- Bump `docker-compose.yml` to the `postgres:18` image, and move the `pgdata` volume mount from `/var/lib/postgresql/data` to `/var/lib/postgresql` — the 18+ images refuse to start with a volume mounted at the old path (see [docker-library/postgres#1259](https://github.com/docker-library/postgres/pull/1259)); verified with a full `docker compose up`
- Set `POSTGRES_DB: pagila` in `docker-compose.yml` (and fix `restore-pagila-data-jsonb.sh` to restore into it) so `docker-compose up` actually loads data into a `pagila` database, matching the README's own `\c pagila` instructions instead of silently loading everything into the default `postgres` database
- Add a `uuid` column (`DEFAULT uuidv7()`, unique-indexed) to `customer`, `rental`, and `payment`, demonstrating PostgreSQL 18's new UUID functions
- Regenerate `pagila-insert-data.sql` from the same data as `pagila-data.sql` — it had drifted badly out of sync (e.g. every film's `release_year` was hardcoded to 2006 regardless of the real value), fixes #39
- Fix 400 of the 999 customers added in the 4.0.0 data refresh all being named "ELIZABETH HALL" — an uncorrelated scalar subquery in the name-generation script was evaluated once instead of per-row (the same bug class as the earlier `create_date` fix); regenerated with proper per-row random names
- Add a `Dockerfile` (installing pg_partman from the PGDG apt repo on `postgres:18`) and hand the `payment` table's future partitions over to it instead of creating them by hand, while leaving the existing Jan 2022 - Jul 2026 partitions untouched; maintenance runs via `scripts/run_partman_maintenance.sh` on cron (`partman.run_maintenance_proc(0, true, true)`) rather than pg_partman's own background worker, and `scripts/add_monthly_data.sh` calls the same procedure as a safety net

Version 3.1.0

This is a maintenance release by 5 contributors:

- Format 2nd list of relations. by @michelc in https://github.com/devrimgunduz/pagila/pull/20
- pgAdmin by @Qoyyuum in https://github.com/devrimgunduz/pagila/pull/27
- Container name in Docker Compose by @Qoyyuum in https://github.com/devrimgunduz/pagila/pull/24
- Sakila Link by @Qoyyuum in https://github.com/devrimgunduz/pagila/pull/25
- Schema Diagram by @Qoyyuum in https://github.com/devrimgunduz/pagila/pull/26

Version 3.0.0

- Add JSONB sample data (based on the packages at apt.postgresql.org and yum.postgresql.org)
- Add docker compose support ( contributed by https://github.com/theothermattm ) https://github.com/devrimgunduz/pagila/pull/16
- Add steps to create pagila database on docker by @dedeco in https://github.com/devrimgunduz/pagila/pull/13
- Add missing user argument by @zOxta in https://github.com/devrimgunduz/pagila/pull/14
- Update dates to 2022
- Fix various issues reported in Github

Version 2.1.0

- Replace varchar(n) with text (David Fetter)
- Match foreign key and primary key data type in some tables (Ganeshan Venkataraman)
- Change CREATE TABLE statement for customer table to use
  DEFAULT nextval('customer_customer_id_seq'::regclass) for customer_id
  field instead of SERIAL (Adrian Klaver).

Version 2.0

- Update schema for newer PostgreSQL versions
- Remove RULE for partitioning, add trigger support.
- Update years in sample data.
- Remove ARTICLES section from README, all links are dead.

Version 0.10.1

- Add pagila-data-insert.sql file, added articles section

Version 0.10

- Support for built-in fulltext. Add enum example

Version 0.9

- Add table partitioning example

Version 0.8

- First release of pagila

## CREATE DATABASE ON [DOCKER](https://docs.docker.com/)

1. On terminal pull the latest postgres image:

```
 docker pull postgres
```

2. Run image:

```
 docker run --name postgres -e POSTGRES_PASSWORD=secret -d postgres
```

3. Run postgres and create the database:

```
docker exec -it postgres psql -U postgres
```

```
psql (13.1 (Debian 13.1-1.pgdg100+1))
Type "help" for help.

postgres=# CREATE DATABASE pagila;
postgres-# CREATE DATABASE
postgres=\q
```

4. Create all schema objetcs (tables, etc) replace `<local-repo>` by your local directory :

```
cat <local-repo>/pagila-schema.sql | docker exec -i postgres psql -U postgres -d pagila
```

5. Insert all data:

```
cat <local-repo>/pagila-data.sql | docker exec -i postgres psql -U postgres -d pagila
```

6. Done! Just use:

```
docker exec -it postgres psql -U postgres
```

````
postgres
psql (13.1 (Debian 13.1-1.pgdg100+1))
Type "help" for help.

postgres=# \c pagila
You are now connected to database "pagila" as user "postgres".
pagila=# \dt
                    List of relations
 Schema |       Name       |       Type        |  Owner
--------+------------------+-------------------+----------
 public | actor            | table             | postgres
 public | address          | table             | postgres
 public | category         | table             | postgres
 public | city             | table             | postgres
 public | country          | table             | postgres
 public | customer         | table             | postgres
 public | film             | table             | postgres
 public | film_actor       | table             | postgres
 public | film_category    | table             | postgres
 public | inventory        | table             | postgres
 public | language         | table             | postgres
 public | payment          | partitioned table | postgres
 public | payment_p2022_01 | table             | postgres
 public | payment_p2022_02 | table             | postgres
 public | payment_p2022_03 | table             | postgres
 public | payment_p2022_04 | table             | postgres
 public | payment_p2022_05 | table             | postgres
 public | payment_p2022_06 | table             | postgres
 public | payment_p2022_07 | table             | postgres
 public | rental           | table             | postgres
 public | staff            | table             | postgres
 public | store            | table             | postgres
(21 rows)

pagila=#
```
````

## CREATE DATABASE ON [DOCKER-COMPOSE](https://docs.docker.com/compose/)

1. Run:

```
docker-compose up
```

2. Done! Just use:

```
docker exec -it pagila psql -U postgres
```

```

postgres
psql (13.1 (Debian 13.1-1.pgdg100+1))
Type "help" for help.

postgres=# \c pagila
You are now connected to database "pagila" as user "postgres".
pagila=# \dt
                    List of relations
 Schema |       Name       |       Type        |  Owner
--------+------------------+-------------------+----------
 public | actor            | table             | postgres
 public | address          | table             | postgres
 public | category         | table             | postgres
 public | city             | table             | postgres
 public | country          | table             | postgres
 public | customer         | table             | postgres
 public | film             | table             | postgres
 public | film_actor       | table             | postgres
 public | film_category    | table             | postgres
 public | inventory        | table             | postgres
 public | language         | table             | postgres
 public | payment          | partitioned table | postgres
 public | payment_p2022_01 | table             | postgres
 public | payment_p2022_02 | table             | postgres
 public | payment_p2022_03 | table             | postgres
 public | payment_p2022_04 | table             | postgres
 public | payment_p2022_05 | table             | postgres
 public | payment_p2022_06 | table             | postgres
 public | payment_p2022_07 | table             | postgres
 public | rental           | table             | postgres
 public | staff            | table             | postgres
 public | store            | table             | postgres
(21 rows)

pagila=#

```
