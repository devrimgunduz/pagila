-- SQL/PGQ (property graph queries, ISO/IEC 9075-16) over the existing
-- Pagila tables. Requires PostgreSQL 19 or later -- CREATE PROPERTY GRAPH
-- and GRAPH_TABLE don't exist on earlier versions -- so this isn't wired
-- into docker-compose.yml (which targets postgres:18); run it by hand
-- against a PostgreSQL 19+ instance after pagila-schema.sql/pagila-data.sql.
--
-- No new data or tables: a property graph is a read-only relational view.
-- `actor`, `film`, and `category` become graph vertices, and the existing
-- `film_actor`/`film_category` join tables -- already primary-keyed on
-- their (source, destination) column pairs -- become graph edges exactly
-- as they already exist. See the "SQL/PGQ" section of the README for
-- example GRAPH_TABLE queries against this graph.

CREATE PROPERTY GRAPH pagila_graph
  VERTEX TABLES (
    actor
      KEY (actor_id)
      LABEL actor PROPERTIES (actor_id, first_name, last_name),
    film
      KEY (film_id)
      LABEL film PROPERTIES (film_id, title, release_year, rating),
    category
      KEY (category_id)
      LABEL category PROPERTIES (category_id, name)
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
