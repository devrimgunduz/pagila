# Pagila

Pagila started as a port of the [Sakila](https://dev.mysql.com/doc/sakila/en/) example database available for MySQL, which was
originally developed by Mike Hillyer of the MySQL AB documentation team. It
is intended to provide a standard schema that can be used for examples in
books, tutorials, articles, samples, etc.

Pagila has been tested against PostgreSQL 12 and above.

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

## PARTITIONED TABLES

The payment table is designed as a partitioned table, with one partition per
calendar month. `pagila-schema.sql` currently ships partitions covering
January 2022 through July 2026; see "KEEPING DATA FRESH" below for how to
add new months as time goes on.

## KEEPING DATA FRESH

`scripts/add_monthly_data.sh` populates one calendar month of new,
realistic rental/payment activity into a running pagila database,
creating that month's `payment` partition first if it doesn't exist yet.
It's meant to be run once a month (e.g. via cron) against a long-lived
pagila instance so the data keeps looking current instead of going stale.

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

It's safe to re-run for the same month: partition creation is skipped if
the partition already exists, and re-running the data step just appends
another batch of activity for that month.

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

Version 4.0.0

- Refresh `pagila-data.sql` with more diverse, less repetitive sample data:
  - Grow the customer base from 599 to 999, with signups spread across 2022-2026 instead of a single date
  - Grow rental activity from ~16k to ~51.8k rows, and payments from ~16k to ~51k rows, spanning January 2022 through July 2026 instead of a few months in 2022
  - Randomize `last_update`/`create_date` timestamps across all tables instead of reusing one fixed value per table
- Add 48 new monthly partitions to the `payment` table in `pagila-schema.sql` (Aug 2022 - Jul 2026) to support the extended date range
- Add `scripts/add_monthly_data.sh` to keep a running pagila instance current: creates the next `payment` partition and populates a month of new rental/payment activity, meant to be scheduled monthly
- Rework the `actor_info` view to return a JSONB column (film titles grouped by category) instead of a concatenated text string, so it's a domain-relevant example for practicing JSONB operators (fixes #21)
- Change `language.name` from `character(20)` to `text`, and strip the trailing blank-padding it left in the shipped data, matching the `text`-everywhere convention used by every other column (fixes #33)

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
