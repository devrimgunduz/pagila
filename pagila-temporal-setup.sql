-- Application-time temporal support (SQL:2011 / ISO/IEC 9075-2) added in
-- PostgreSQL 19: WITHOUT OVERLAPS primary/unique keys and temporal foreign
-- keys built on range-typed columns, plus native UPDATE/DELETE ... FOR
-- PORTION OF DML that splits a row at the edges of the portion being
-- changed. Requires PostgreSQL 19+, newer than this project's
-- postgres:18-based docker-compose.yml, so this isn't wired into the
-- compose pipeline; run it by hand, after pagila-schema.sql/pagila-data.sql,
-- against a PostgreSQL 19+ instance. See the "TEMPORAL TABLES" section of
-- the README for example queries.

-- WITHOUT OVERLAPS is implemented as a GiST exclusion constraint under the
-- hood, so the non-range columns in the key (film_id, store_id, ...) need
-- a GiST-compatible equality operator class, which btree_gist supplies.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- film_price_history: film.rental_rate/replacement_cost as they've
-- actually changed over the title's life, one row per validity period.
-- WITHOUT OVERLAPS on (film_id, valid_at) enforces that a given film can't
-- have two price periods in effect at once.
CREATE TABLE film_price_history (
    film_id integer NOT NULL REFERENCES film (film_id),
    rental_rate numeric(4,2) NOT NULL,
    replacement_cost numeric(5,2) NOT NULL,
    valid_at daterange NOT NULL,
    PRIMARY KEY (film_id, valid_at WITHOUT OVERLAPS)
);

-- store_film_price_override: a store's own rental rate for a film during
-- some sub-period. The temporal foreign key (PERIOD valid_at) requires
-- every override period to fall within a period where film_price_history
-- actually has that film on record -- not just overlap it.
CREATE TABLE store_film_price_override (
    store_id integer NOT NULL REFERENCES store (store_id),
    film_id integer NOT NULL,
    rental_rate numeric(4,2) NOT NULL,
    valid_at daterange NOT NULL,
    PRIMARY KEY (store_id, film_id, valid_at WITHOUT OVERLAPS),
    FOREIGN KEY (film_id, PERIOD valid_at) REFERENCES film_price_history (film_id, PERIOD valid_at)
);

-- ACADEMY DINOSAUR (film_id 1): launched at a new-release price, discounted
-- twice as it aged, ending at its current film.rental_rate/replacement_cost
-- (0.99 / 20.99).
INSERT INTO film_price_history (film_id, rental_rate, replacement_cost, valid_at) VALUES
    (1, 4.99, 24.99, daterange('2022-01-01', '2023-01-01')),
    (1, 2.99, 22.99, daterange('2023-01-01', '2024-06-01')),
    (1, 0.99, 20.99, daterange('2024-06-01', NULL));

-- ACE GOLDFINGER (film_id 2): a shorter history, at its current price
-- (4.99 / 12.99) throughout -- demonstrates WITHOUT OVERLAPS is scoped per
-- film_id: this period overlaps ACADEMY DINOSAUR's rows on the calendar,
-- which is fine, since they're different keys.
INSERT INTO film_price_history (film_id, rental_rate, replacement_cost, valid_at) VALUES
    (2, 4.99, 12.99, daterange('2023-01-01', NULL));

-- Store 1 discounts ACADEMY DINOSAUR for a spring promotion, entirely
-- within the 2023-01-01..2024-06-01 base price period above.
INSERT INTO store_film_price_override (store_id, film_id, rental_rate, valid_at) VALUES
    (1, 1, 1.99, daterange('2023-03-01', '2023-06-01'));

-- Store 2 runs its own, cheaper everyday rate for ACADEMY DINOSAUR,
-- entirely within the current (open-ended) base price period.
INSERT INTO store_film_price_override (store_id, film_id, rental_rate, valid_at) VALUES
    (2, 1, 0.79, daterange('2024-06-01', NULL));

-- A one-month summer promotion cuts ACADEMY DINOSAUR's base rate further,
-- splitting the open-ended 0.99 row into three: before, during, and after
-- the promotion. See the "TEMPORAL TABLES" section of the README for the
-- row-by-row result and how FOR PORTION OF differs from a plain UPDATE.
UPDATE film_price_history
FOR PORTION OF valid_at FROM '2024-07-01' TO '2024-08-01'
SET rental_rate = 0.49
WHERE film_id = 1;

-- ACE GOLDFINGER is pulled from the catalog for a month, splitting its
-- single open-ended row into a bounded one and a new open-ended one, with
-- a June gap where the film has no price on record at all.
DELETE FROM film_price_history
FOR PORTION OF valid_at FROM '2023-06-01' TO '2023-07-01'
WHERE film_id = 2;
