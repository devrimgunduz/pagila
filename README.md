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

## PARTITIONED TABLES

The payment table is designed as a partitioned table with a 7 month timespan
for the date ranges.

## INSTALL NOTE

The pagila-data.sql file and the pagila-insert-data.sql both contain the same
data, the former using COPY commands, the latter using INSERT commands, so you
only need to install one of them. Both formats are provided for those who have
trouble using one version or another, and for instructors who want to point out
the longer data loading time with the latter. You can load them via psql, pgAdmin, etc.

Since JSONB data is quite large to store on Github, the backup is not a plain SQL
file. You can still use psql/pgAdmin, etc. to load pagila-schema-jsonb.sql, however
please use pg_restore to load jsonb data files:

```
pg_restore /usr/share/pagila/pagila-data-yum-jsonb.sql -U postgres -d pagila
pg_restore /usr/share/pagila/pagila-data-apt-jsonb.sql -U postgres -d pagila
```

## VERSION HISTORY

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
