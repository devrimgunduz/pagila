--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.3
-- Dumped by pg_dump version 10beta1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- Name: mpaa_rating; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE mpaa_rating AS ENUM (
    'G',
    'PG',
    'PG-13',
    'R',
    'NC-17'
);


ALTER TYPE mpaa_rating OWNER TO postgres;

--
-- Name: year; Type: DOMAIN; Schema: public; Owner: postgres
--

CREATE DOMAIN year AS integer
	CONSTRAINT year_check CHECK (((VALUE >= 1901) AND (VALUE <= 2155)));


ALTER DOMAIN year OWNER TO postgres;

--
-- Name: _group_concat(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION _group_concat(text, text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT CASE
  WHEN $2 IS NULL THEN $1
  WHEN $1 IS NULL THEN $2
  ELSE $1 || ', ' || $2
END
$_$;


ALTER FUNCTION public._group_concat(text, text) OWNER TO postgres;

--
-- Name: film_in_stock(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION film_in_stock(p_film_id integer, p_store_id integer, OUT p_film_count integer) RETURNS SETOF integer
    LANGUAGE sql
    AS $_$
     SELECT inventory_id
     FROM inventory
     WHERE film_id = $1
     AND store_id = $2
     AND inventory_in_stock(inventory_id);
$_$;


ALTER FUNCTION public.film_in_stock(p_film_id integer, p_store_id integer, OUT p_film_count integer) OWNER TO postgres;

--
-- Name: film_not_in_stock(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION film_not_in_stock(p_film_id integer, p_store_id integer, OUT p_film_count integer) RETURNS SETOF integer
    LANGUAGE sql
    AS $_$
    SELECT inventory_id
    FROM inventory
    WHERE film_id = $1
    AND store_id = $2
    AND NOT inventory_in_stock(inventory_id);
$_$;


ALTER FUNCTION public.film_not_in_stock(p_film_id integer, p_store_id integer, OUT p_film_count integer) OWNER TO postgres;

--
-- Name: get_customer_balance(integer, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION get_customer_balance(p_customer_id integer, p_effective_date timestamp without time zone) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
       --#OK, WE NEED TO CALCULATE THE CURRENT BALANCE GIVEN A CUSTOMER_ID AND A DATE
       --#THAT WE WANT THE BALANCE TO BE EFFECTIVE FOR. THE BALANCE IS:
       --#   1) RENTAL FEES FOR ALL PREVIOUS RENTALS
       --#   2) ONE DOLLAR FOR EVERY DAY THE PREVIOUS RENTALS ARE OVERDUE
       --#   3) IF A FILM IS MORE THAN RENTAL_DURATION * 2 OVERDUE, CHARGE THE REPLACEMENT_COST
       --#   4) SUBTRACT ALL PAYMENTS MADE BEFORE THE DATE SPECIFIED
DECLARE
    v_rentfees DECIMAL(5,2); --#FEES PAID TO RENT THE VIDEOS INITIALLY
    v_overfees INTEGER;      --#LATE FEES FOR PRIOR RENTALS
    v_payments DECIMAL(5,2); --#SUM OF PAYMENTS MADE PREVIOUSLY
BEGIN
    SELECT COALESCE(SUM(film.rental_rate),0) INTO v_rentfees
    FROM film, inventory, rental
    WHERE film.film_id = inventory.film_id
      AND inventory.inventory_id = rental.inventory_id
      AND rental.rental_date <= p_effective_date
      AND rental.customer_id = p_customer_id;

    SELECT COALESCE(SUM(IF((rental.return_date - rental.rental_date) > (film.rental_duration * '1 day'::interval),
        ((rental.return_date - rental.rental_date) - (film.rental_duration * '1 day'::interval)),0)),0) INTO v_overfees
    FROM rental, inventory, film
    WHERE film.film_id = inventory.film_id
      AND inventory.inventory_id = rental.inventory_id
      AND rental.rental_date <= p_effective_date
      AND rental.customer_id = p_customer_id;

    SELECT COALESCE(SUM(payment.amount),0) INTO v_payments
    FROM payment
    WHERE payment.payment_date <= p_effective_date
    AND payment.customer_id = p_customer_id;

    RETURN v_rentfees + v_overfees - v_payments;
END
$$;


ALTER FUNCTION public.get_customer_balance(p_customer_id integer, p_effective_date timestamp without time zone) OWNER TO postgres;

--
-- Name: inventory_held_by_customer(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION inventory_held_by_customer(p_inventory_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_customer_id INTEGER;
BEGIN

  SELECT customer_id INTO v_customer_id
  FROM rental
  WHERE return_date IS NULL
  AND inventory_id = p_inventory_id;

  RETURN v_customer_id;
END $$;


ALTER FUNCTION public.inventory_held_by_customer(p_inventory_id integer) OWNER TO postgres;

--
-- Name: inventory_in_stock(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION inventory_in_stock(p_inventory_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rentals INTEGER;
    v_out     INTEGER;
BEGIN
    -- AN ITEM IS IN-STOCK IF THERE ARE EITHER NO ROWS IN THE rental TABLE
    -- FOR THE ITEM OR ALL ROWS HAVE return_date POPULATED

    SELECT count(*) INTO v_rentals
    FROM rental
    WHERE inventory_id = p_inventory_id;

    IF v_rentals = 0 THEN
      RETURN TRUE;
    END IF;

    SELECT COUNT(rental_id) INTO v_out
    FROM inventory LEFT JOIN rental USING(inventory_id)
    WHERE inventory.inventory_id = p_inventory_id
    AND rental.return_date IS NULL;

    IF v_out > 0 THEN
      RETURN FALSE;
    ELSE
      RETURN TRUE;
    END IF;
END $$;


ALTER FUNCTION public.inventory_in_stock(p_inventory_id integer) OWNER TO postgres;

--
-- Name: last_day(timestamp without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION last_day(timestamp without time zone) RETURNS date
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
  SELECT CASE
    WHEN EXTRACT(MONTH FROM $1) = 12 THEN
      (((EXTRACT(YEAR FROM $1) + 1) operator(pg_catalog.||) '-01-01')::date - INTERVAL '1 day')::date
    ELSE
      ((EXTRACT(YEAR FROM $1) operator(pg_catalog.||) '-' operator(pg_catalog.||) (EXTRACT(MONTH FROM $1) + 1) operator(pg_catalog.||) '-01')::date - INTERVAL '1 day')::date
    END
$_$;


ALTER FUNCTION public.last_day(timestamp without time zone) OWNER TO postgres;

--
-- Name: last_updated(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION last_updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.last_update = CURRENT_TIMESTAMP;
    RETURN NEW;
END $$;


ALTER FUNCTION public.last_updated() OWNER TO postgres;

--
-- Name: pagila_payment_insert_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION pagila_payment_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	IF (NEW.tarih >= '2017-01-01' AND NEW.tarih < '2017-02-01' ) THEN
		INSERT INTO payment_p2017_01 VALUES (NEW.*);
	ELSIF (NEW.tarih >= '2017-02-01' AND NEW.tarih < '2017-03-01' ) THEN
                INSERT INTO payment_p2017_02 VALUES (NEW.*);
	ELSIF (NEW.tarih >= '2017-03-01' AND NEW.tarih < '2017-04-01' ) THEN
                INSERT INTO payment_p2017_03 VALUES (NEW.*);
	ELSIF (NEW.tarih >= '2017-04-01' AND NEW.tarih < '2017-05-01' ) THEN
                INSERT INTO payment_p2017_04 VALUES (NEW.*);
	ELSIF (NEW.tarih >= '2017-05-01' AND NEW.tarih < '2017-06-01' ) THEN
                INSERT INTO payment_p2017_05 VALUES (NEW.*);
	ELSIF (NEW.tarih >= '2017-06-01' AND NEW.tarih < '2017-07-01' ) THEN
                INSERT INTO payment_p2017_06 VALUES (NEW.*);
	ELSE
            	RAISE EXCEPTION 'Missing partition!' ;
        END IF;
        RETURN NULL;
END;
$$;


ALTER FUNCTION public.pagila_payment_insert_trigger() OWNER TO postgres;

--
-- Name: customer_customer_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE customer_customer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE customer_customer_id_seq OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: customer; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE customer (
    customer_id integer DEFAULT nextval('customer_customer_id_seq'::regclass) NOT NULL,
    store_id smallint NOT NULL,
    first_name character varying(45) NOT NULL,
    last_name character varying(45) NOT NULL,
    email character varying(50),
    address_id smallint NOT NULL,
    activebool boolean DEFAULT true NOT NULL,
    create_date date DEFAULT ('now'::text)::date NOT NULL,
    last_update timestamp without time zone DEFAULT now(),
    active integer
);


ALTER TABLE customer OWNER TO postgres;

--
-- Name: rewards_report(integer, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION rewards_report(min_monthly_purchases integer, min_dollar_amount_purchased numeric) RETURNS SETOF customer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
DECLARE
    last_month_start DATE;
    last_month_end DATE;
rr RECORD;
tmpSQL TEXT;
BEGIN

    /* Some sanity checks... */
    IF min_monthly_purchases = 0 THEN
        RAISE EXCEPTION 'Minimum monthly purchases parameter must be > 0';
    END IF;
    IF min_dollar_amount_purchased = 0.00 THEN
        RAISE EXCEPTION 'Minimum monthly dollar amount purchased parameter must be > $0.00';
    END IF;

    last_month_start := CURRENT_DATE - '3 month'::interval;
    last_month_start := to_date((extract(YEAR FROM last_month_start) || '-' || extract(MONTH FROM last_month_start) || '-01'),'YYYY-MM-DD');
    last_month_end := LAST_DAY(last_month_start);

    /*
    Create a temporary storage area for Customer IDs.
    */
    CREATE TEMPORARY TABLE tmpCustomer (customer_id INTEGER NOT NULL PRIMARY KEY);

    /*
    Find all customers meeting the monthly purchase requirements
    */

    tmpSQL := 'INSERT INTO tmpCustomer (customer_id)
        SELECT p.customer_id
        FROM payment AS p
        WHERE DATE(p.payment_date) BETWEEN '||quote_literal(last_month_start) ||' AND '|| quote_literal(last_month_end) || '
        GROUP BY customer_id
        HAVING SUM(p.amount) > '|| min_dollar_amount_purchased || '
        AND COUNT(customer_id) > ' ||min_monthly_purchases ;

    EXECUTE tmpSQL;

    /*
    Output ALL customer information of matching rewardees.
    Customize output as needed.
    */
    FOR rr IN EXECUTE 'SELECT c.* FROM tmpCustomer AS t INNER JOIN customer AS c ON t.customer_id = c.customer_id' LOOP
        RETURN NEXT rr;
    END LOOP;

    /* Clean up */
    tmpSQL := 'DROP TABLE tmpCustomer';
    EXECUTE tmpSQL;

RETURN;
END
$_$;


ALTER FUNCTION public.rewards_report(min_monthly_purchases integer, min_dollar_amount_purchased numeric) OWNER TO postgres;

--
-- Name: group_concat(text); Type: AGGREGATE; Schema: public; Owner: postgres
--

CREATE AGGREGATE group_concat(text) (
    SFUNC = _group_concat,
    STYPE = text
);


ALTER AGGREGATE public.group_concat(text) OWNER TO postgres;

--
-- Name: actor_actor_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE actor_actor_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE actor_actor_id_seq OWNER TO postgres;

--
-- Name: actor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE actor (
    actor_id integer DEFAULT nextval('actor_actor_id_seq'::regclass) NOT NULL,
    first_name character varying(45) NOT NULL,
    last_name character varying(45) NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE actor OWNER TO postgres;

--
-- Name: category_category_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE category_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE category_category_id_seq OWNER TO postgres;

--
-- Name: category; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE category (
    category_id integer DEFAULT nextval('category_category_id_seq'::regclass) NOT NULL,
    name character varying(25) NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE category OWNER TO postgres;

--
-- Name: film_film_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE film_film_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE film_film_id_seq OWNER TO postgres;

--
-- Name: film; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE film (
    film_id integer DEFAULT nextval('film_film_id_seq'::regclass) NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    release_year year,
    language_id smallint NOT NULL,
    original_language_id smallint,
    rental_duration smallint DEFAULT 3 NOT NULL,
    rental_rate numeric(4,2) DEFAULT 4.99 NOT NULL,
    length smallint,
    replacement_cost numeric(5,2) DEFAULT 19.99 NOT NULL,
    rating mpaa_rating DEFAULT 'G'::mpaa_rating,
    last_update timestamp without time zone DEFAULT now() NOT NULL,
    special_features text[],
    fulltext tsvector NOT NULL
);


ALTER TABLE film OWNER TO postgres;

--
-- Name: film_actor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE film_actor (
    actor_id smallint NOT NULL,
    film_id smallint NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE film_actor OWNER TO postgres;

--
-- Name: film_category; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE film_category (
    film_id smallint NOT NULL,
    category_id smallint NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE film_category OWNER TO postgres;

--
-- Name: actor_info; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW actor_info AS
 SELECT a.actor_id,
    a.first_name,
    a.last_name,
    group_concat(DISTINCT (((c.name)::text || ': '::text) || ( SELECT group_concat((f.title)::text) AS group_concat
           FROM ((film f
             JOIN film_category fc_1 ON ((f.film_id = fc_1.film_id)))
             JOIN film_actor fa_1 ON ((f.film_id = fa_1.film_id)))
          WHERE ((fc_1.category_id = c.category_id) AND (fa_1.actor_id = a.actor_id))
          GROUP BY fa_1.actor_id))) AS film_info
   FROM (((actor a
     LEFT JOIN film_actor fa ON ((a.actor_id = fa.actor_id)))
     LEFT JOIN film_category fc ON ((fa.film_id = fc.film_id)))
     LEFT JOIN category c ON ((fc.category_id = c.category_id)))
  GROUP BY a.actor_id, a.first_name, a.last_name;


ALTER TABLE actor_info OWNER TO postgres;

--
-- Name: address_address_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE address_address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE address_address_id_seq OWNER TO postgres;

--
-- Name: address; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE address (
    address_id integer DEFAULT nextval('address_address_id_seq'::regclass) NOT NULL,
    address character varying(50) NOT NULL,
    address2 character varying(50),
    district character varying(20) NOT NULL,
    city_id smallint NOT NULL,
    postal_code character varying(10),
    phone character varying(20) NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE address OWNER TO postgres;

--
-- Name: city_city_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE city_city_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE city_city_id_seq OWNER TO postgres;

--
-- Name: city; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE city (
    city_id integer DEFAULT nextval('city_city_id_seq'::regclass) NOT NULL,
    city character varying(50) NOT NULL,
    country_id smallint NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE city OWNER TO postgres;

--
-- Name: country_country_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE country_country_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE country_country_id_seq OWNER TO postgres;

--
-- Name: country; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE country (
    country_id integer DEFAULT nextval('country_country_id_seq'::regclass) NOT NULL,
    country character varying(50) NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE country OWNER TO postgres;

--
-- Name: customer_list; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW customer_list AS
 SELECT cu.customer_id AS id,
    (((cu.first_name)::text || ' '::text) || (cu.last_name)::text) AS name,
    a.address,
    a.postal_code AS "zip code",
    a.phone,
    city.city,
    country.country,
        CASE
            WHEN cu.activebool THEN 'active'::text
            ELSE ''::text
        END AS notes,
    cu.store_id AS sid
   FROM (((customer cu
     JOIN address a ON ((cu.address_id = a.address_id)))
     JOIN city ON ((a.city_id = city.city_id)))
     JOIN country ON ((city.country_id = country.country_id)));


ALTER TABLE customer_list OWNER TO postgres;

--
-- Name: film_list; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW film_list AS
 SELECT film.film_id AS fid,
    film.title,
    film.description,
    category.name AS category,
    film.rental_rate AS price,
    film.length,
    film.rating,
    group_concat((((actor.first_name)::text || ' '::text) || (actor.last_name)::text)) AS actors
   FROM ((((category
     LEFT JOIN film_category ON ((category.category_id = film_category.category_id)))
     LEFT JOIN film ON ((film_category.film_id = film.film_id)))
     JOIN film_actor ON ((film.film_id = film_actor.film_id)))
     JOIN actor ON ((film_actor.actor_id = actor.actor_id)))
  GROUP BY film.film_id, film.title, film.description, category.name, film.rental_rate, film.length, film.rating;


ALTER TABLE film_list OWNER TO postgres;

--
-- Name: inventory_inventory_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE inventory_inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE inventory_inventory_id_seq OWNER TO postgres;

--
-- Name: inventory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE inventory (
    inventory_id integer DEFAULT nextval('inventory_inventory_id_seq'::regclass) NOT NULL,
    film_id smallint NOT NULL,
    store_id smallint NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE inventory OWNER TO postgres;

--
-- Name: language_language_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE language_language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE language_language_id_seq OWNER TO postgres;

--
-- Name: language; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE language (
    language_id integer DEFAULT nextval('language_language_id_seq'::regclass) NOT NULL,
    name character(20) NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE language OWNER TO postgres;

--
-- Name: nicer_but_slower_film_list; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW nicer_but_slower_film_list AS
 SELECT film.film_id AS fid,
    film.title,
    film.description,
    category.name AS category,
    film.rental_rate AS price,
    film.length,
    film.rating,
    group_concat((((upper("substring"((actor.first_name)::text, 1, 1)) || lower("substring"((actor.first_name)::text, 2))) || upper("substring"((actor.last_name)::text, 1, 1))) || lower("substring"((actor.last_name)::text, 2)))) AS actors
   FROM ((((category
     LEFT JOIN film_category ON ((category.category_id = film_category.category_id)))
     LEFT JOIN film ON ((film_category.film_id = film.film_id)))
     JOIN film_actor ON ((film.film_id = film_actor.film_id)))
     JOIN actor ON ((film_actor.actor_id = actor.actor_id)))
  GROUP BY film.film_id, film.title, film.description, category.name, film.rental_rate, film.length, film.rating;


ALTER TABLE nicer_but_slower_film_list OWNER TO postgres;

--
-- Name: payment_payment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE payment_payment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE payment_payment_id_seq OWNER TO postgres;

--
-- Name: payment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE payment (
    payment_id integer DEFAULT nextval('payment_payment_id_seq'::regclass) NOT NULL,
    customer_id smallint NOT NULL,
    staff_id smallint NOT NULL,
    rental_id integer NOT NULL,
    amount numeric(5,2) NOT NULL,
    payment_date timestamp without time zone NOT NULL
);


ALTER TABLE payment OWNER TO postgres;

--
-- Name: payment_p2017_01; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE payment_p2017_01 (
    CONSTRAINT payment_p2017_01_payment_date_check CHECK (((payment_date >= '2017-01-01 00:00:00'::timestamp without time zone) AND (payment_date < '2017-02-01 00:00:00'::timestamp without time zone)))
)
INHERITS (payment);


ALTER TABLE payment_p2017_01 OWNER TO postgres;

--
-- Name: payment_p2017_02; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE payment_p2017_02 (
    CONSTRAINT payment_p2017_02_payment_date_check CHECK (((payment_date >= '2017-02-01 00:00:00'::timestamp without time zone) AND (payment_date < '2017-03-01 00:00:00'::timestamp without time zone)))
)
INHERITS (payment);


ALTER TABLE payment_p2017_02 OWNER TO postgres;

--
-- Name: payment_p2017_03; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE payment_p2017_03 (
    CONSTRAINT payment_p2017_03_payment_date_check CHECK (((payment_date >= '2017-03-01 00:00:00'::timestamp without time zone) AND (payment_date < '2017-04-01 00:00:00'::timestamp without time zone)))
)
INHERITS (payment);


ALTER TABLE payment_p2017_03 OWNER TO postgres;

--
-- Name: payment_p2017_04; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE payment_p2017_04 (
    CONSTRAINT payment_p2017_04_payment_date_check CHECK (((payment_date >= '2017-04-01 00:00:00'::timestamp without time zone) AND (payment_date < '2017-05-01 00:00:00'::timestamp without time zone)))
)
INHERITS (payment);


ALTER TABLE payment_p2017_04 OWNER TO postgres;

--
-- Name: payment_p2017_05; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE payment_p2017_05 (
    CONSTRAINT payment_p2017_05_payment_date_check CHECK (((payment_date >= '2017-05-01 00:00:00'::timestamp without time zone) AND (payment_date < '2017-06-01 00:00:00'::timestamp without time zone)))
)
INHERITS (payment);


ALTER TABLE payment_p2017_05 OWNER TO postgres;

--
-- Name: payment_p2017_06; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE payment_p2017_06 (
    CONSTRAINT payment_p2017_06_payment_date_check CHECK (((payment_date >= '2017-06-01 00:00:00'::timestamp without time zone) AND (payment_date < '2017-07-01 00:00:00'::timestamp without time zone)))
)
INHERITS (payment);


ALTER TABLE payment_p2017_06 OWNER TO postgres;

--
-- Name: rental_rental_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE rental_rental_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rental_rental_id_seq OWNER TO postgres;

--
-- Name: rental; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE rental (
    rental_id integer DEFAULT nextval('rental_rental_id_seq'::regclass) NOT NULL,
    rental_date timestamp without time zone NOT NULL,
    inventory_id integer NOT NULL,
    customer_id smallint NOT NULL,
    return_date timestamp without time zone,
    staff_id smallint NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE rental OWNER TO postgres;

--
-- Name: sales_by_film_category; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW sales_by_film_category AS
 SELECT c.name AS category,
    sum(p.amount) AS total_sales
   FROM (((((payment p
     JOIN rental r ON ((p.rental_id = r.rental_id)))
     JOIN inventory i ON ((r.inventory_id = i.inventory_id)))
     JOIN film f ON ((i.film_id = f.film_id)))
     JOIN film_category fc ON ((f.film_id = fc.film_id)))
     JOIN category c ON ((fc.category_id = c.category_id)))
  GROUP BY c.name
  ORDER BY (sum(p.amount)) DESC;


ALTER TABLE sales_by_film_category OWNER TO postgres;

--
-- Name: staff_staff_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE staff_staff_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE staff_staff_id_seq OWNER TO postgres;

--
-- Name: staff; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE staff (
    staff_id integer DEFAULT nextval('staff_staff_id_seq'::regclass) NOT NULL,
    first_name character varying(45) NOT NULL,
    last_name character varying(45) NOT NULL,
    address_id smallint NOT NULL,
    email character varying(50),
    store_id smallint NOT NULL,
    active boolean DEFAULT true NOT NULL,
    username character varying(16) NOT NULL,
    password character varying(40),
    last_update timestamp without time zone DEFAULT now() NOT NULL,
    picture bytea
);


ALTER TABLE staff OWNER TO postgres;

--
-- Name: store_store_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE store_store_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE store_store_id_seq OWNER TO postgres;

--
-- Name: store; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE store (
    store_id integer DEFAULT nextval('store_store_id_seq'::regclass) NOT NULL,
    manager_staff_id smallint NOT NULL,
    address_id smallint NOT NULL,
    last_update timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE store OWNER TO postgres;

--
-- Name: sales_by_store; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW sales_by_store AS
 SELECT (((c.city)::text || ','::text) || (cy.country)::text) AS store,
    (((m.first_name)::text || ' '::text) || (m.last_name)::text) AS manager,
    sum(p.amount) AS total_sales
   FROM (((((((payment p
     JOIN rental r ON ((p.rental_id = r.rental_id)))
     JOIN inventory i ON ((r.inventory_id = i.inventory_id)))
     JOIN store s ON ((i.store_id = s.store_id)))
     JOIN address a ON ((s.address_id = a.address_id)))
     JOIN city c ON ((a.city_id = c.city_id)))
     JOIN country cy ON ((c.country_id = cy.country_id)))
     JOIN staff m ON ((s.manager_staff_id = m.staff_id)))
  GROUP BY cy.country, c.city, s.store_id, m.first_name, m.last_name
  ORDER BY cy.country, c.city;


ALTER TABLE sales_by_store OWNER TO postgres;

--
-- Name: staff_list; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW staff_list AS
 SELECT s.staff_id AS id,
    (((s.first_name)::text || ' '::text) || (s.last_name)::text) AS name,
    a.address,
    a.postal_code AS "zip code",
    a.phone,
    city.city,
    country.country,
    s.store_id AS sid
   FROM (((staff s
     JOIN address a ON ((s.address_id = a.address_id)))
     JOIN city ON ((a.city_id = city.city_id)))
     JOIN country ON ((city.country_id = country.country_id)));


ALTER TABLE staff_list OWNER TO postgres;

--
-- Name: payment_p2017_01 payment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_01 ALTER COLUMN payment_id SET DEFAULT nextval('payment_payment_id_seq'::regclass);


--
-- Name: payment_p2017_02 payment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_02 ALTER COLUMN payment_id SET DEFAULT nextval('payment_payment_id_seq'::regclass);


--
-- Name: payment_p2017_03 payment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_03 ALTER COLUMN payment_id SET DEFAULT nextval('payment_payment_id_seq'::regclass);


--
-- Name: payment_p2017_04 payment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_04 ALTER COLUMN payment_id SET DEFAULT nextval('payment_payment_id_seq'::regclass);


--
-- Name: payment_p2017_05 payment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_05 ALTER COLUMN payment_id SET DEFAULT nextval('payment_payment_id_seq'::regclass);


--
-- Name: payment_p2017_06 payment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_06 ALTER COLUMN payment_id SET DEFAULT nextval('payment_payment_id_seq'::regclass);


--
-- Data for Name: actor; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO actor VALUES (1, 'PENELOPE', 'GUINESS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (2, 'NICK', 'WAHLBERG', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (3, 'ED', 'CHASE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (4, 'JENNIFER', 'DAVIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (5, 'JOHNNY', 'LOLLOBRIGIDA', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (6, 'BETTE', 'NICHOLSON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (7, 'GRACE', 'MOSTEL', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (8, 'MATTHEW', 'JOHANSSON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (9, 'JOE', 'SWANK', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (10, 'CHRISTIAN', 'GABLE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (11, 'ZERO', 'CAGE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (12, 'KARL', 'BERRY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (13, 'UMA', 'WOOD', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (14, 'VIVIEN', 'BERGEN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (15, 'CUBA', 'OLIVIER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (16, 'FRED', 'COSTNER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (17, 'HELEN', 'VOIGHT', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (18, 'DAN', 'TORN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (19, 'BOB', 'FAWCETT', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (20, 'LUCILLE', 'TRACY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (21, 'KIRSTEN', 'PALTROW', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (22, 'ELVIS', 'MARX', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (23, 'SANDRA', 'KILMER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (24, 'CAMERON', 'STREEP', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (25, 'KEVIN', 'BLOOM', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (26, 'RIP', 'CRAWFORD', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (27, 'JULIA', 'MCQUEEN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (28, 'WOODY', 'HOFFMAN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (29, 'ALEC', 'WAYNE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (30, 'SANDRA', 'PECK', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (31, 'SISSY', 'SOBIESKI', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (32, 'TIM', 'HACKMAN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (33, 'MILLA', 'PECK', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (34, 'AUDREY', 'OLIVIER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (35, 'JUDY', 'DEAN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (36, 'BURT', 'DUKAKIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (37, 'VAL', 'BOLGER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (38, 'TOM', 'MCKELLEN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (39, 'GOLDIE', 'BRODY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (40, 'JOHNNY', 'CAGE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (41, 'JODIE', 'DEGENERES', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (42, 'TOM', 'MIRANDA', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (43, 'KIRK', 'JOVOVICH', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (44, 'NICK', 'STALLONE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (45, 'REESE', 'KILMER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (46, 'PARKER', 'GOLDBERG', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (47, 'JULIA', 'BARRYMORE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (48, 'FRANCES', 'DAY-LEWIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (49, 'ANNE', 'CRONYN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (50, 'NATALIE', 'HOPKINS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (51, 'GARY', 'PHOENIX', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (52, 'CARMEN', 'HUNT', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (53, 'MENA', 'TEMPLE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (54, 'PENELOPE', 'PINKETT', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (55, 'FAY', 'KILMER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (56, 'DAN', 'HARRIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (57, 'JUDE', 'CRUISE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (58, 'CHRISTIAN', 'AKROYD', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (59, 'DUSTIN', 'TAUTOU', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (60, 'HENRY', 'BERRY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (61, 'CHRISTIAN', 'NEESON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (62, 'JAYNE', 'NEESON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (63, 'CAMERON', 'WRAY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (64, 'RAY', 'JOHANSSON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (65, 'ANGELA', 'HUDSON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (66, 'MARY', 'TANDY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (67, 'JESSICA', 'BAILEY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (68, 'RIP', 'WINSLET', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (69, 'KENNETH', 'PALTROW', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (70, 'MICHELLE', 'MCCONAUGHEY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (71, 'ADAM', 'GRANT', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (72, 'SEAN', 'WILLIAMS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (73, 'GARY', 'PENN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (74, 'MILLA', 'KEITEL', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (75, 'BURT', 'POSEY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (76, 'ANGELINA', 'ASTAIRE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (77, 'CARY', 'MCCONAUGHEY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (78, 'GROUCHO', 'SINATRA', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (79, 'MAE', 'HOFFMAN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (80, 'RALPH', 'CRUZ', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (81, 'SCARLETT', 'DAMON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (82, 'WOODY', 'JOLIE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (83, 'BEN', 'WILLIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (84, 'JAMES', 'PITT', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (85, 'MINNIE', 'ZELLWEGER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (86, 'GREG', 'CHAPLIN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (87, 'SPENCER', 'PECK', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (88, 'KENNETH', 'PESCI', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (89, 'CHARLIZE', 'DENCH', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (90, 'SEAN', 'GUINESS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (91, 'CHRISTOPHER', 'BERRY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (92, 'KIRSTEN', 'AKROYD', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (93, 'ELLEN', 'PRESLEY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (94, 'KENNETH', 'TORN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (95, 'DARYL', 'WAHLBERG', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (96, 'GENE', 'WILLIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (97, 'MEG', 'HAWKE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (98, 'CHRIS', 'BRIDGES', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (99, 'JIM', 'MOSTEL', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (100, 'SPENCER', 'DEPP', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (101, 'SUSAN', 'DAVIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (102, 'WALTER', 'TORN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (103, 'MATTHEW', 'LEIGH', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (104, 'PENELOPE', 'CRONYN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (105, 'SIDNEY', 'CROWE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (106, 'GROUCHO', 'DUNST', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (107, 'GINA', 'DEGENERES', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (108, 'WARREN', 'NOLTE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (109, 'SYLVESTER', 'DERN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (110, 'SUSAN', 'DAVIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (111, 'CAMERON', 'ZELLWEGER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (112, 'RUSSELL', 'BACALL', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (113, 'MORGAN', 'HOPKINS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (114, 'MORGAN', 'MCDORMAND', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (115, 'HARRISON', 'BALE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (116, 'DAN', 'STREEP', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (117, 'RENEE', 'TRACY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (118, 'CUBA', 'ALLEN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (119, 'WARREN', 'JACKMAN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (120, 'PENELOPE', 'MONROE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (121, 'LIZA', 'BERGMAN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (122, 'SALMA', 'NOLTE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (123, 'JULIANNE', 'DENCH', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (124, 'SCARLETT', 'BENING', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (125, 'ALBERT', 'NOLTE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (126, 'FRANCES', 'TOMEI', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (127, 'KEVIN', 'GARLAND', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (128, 'CATE', 'MCQUEEN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (129, 'DARYL', 'CRAWFORD', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (130, 'GRETA', 'KEITEL', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (131, 'JANE', 'JACKMAN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (132, 'ADAM', 'HOPPER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (133, 'RICHARD', 'PENN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (134, 'GENE', 'HOPKINS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (135, 'RITA', 'REYNOLDS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (136, 'ED', 'MANSFIELD', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (137, 'MORGAN', 'WILLIAMS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (138, 'LUCILLE', 'DEE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (139, 'EWAN', 'GOODING', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (140, 'WHOOPI', 'HURT', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (141, 'CATE', 'HARRIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (142, 'JADA', 'RYDER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (143, 'RIVER', 'DEAN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (144, 'ANGELA', 'WITHERSPOON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (145, 'KIM', 'ALLEN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (146, 'ALBERT', 'JOHANSSON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (147, 'FAY', 'WINSLET', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (148, 'EMILY', 'DEE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (149, 'RUSSELL', 'TEMPLE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (150, 'JAYNE', 'NOLTE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (151, 'GEOFFREY', 'HESTON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (152, 'BEN', 'HARRIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (153, 'MINNIE', 'KILMER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (154, 'MERYL', 'GIBSON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (155, 'IAN', 'TANDY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (156, 'FAY', 'WOOD', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (157, 'GRETA', 'MALDEN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (158, 'VIVIEN', 'BASINGER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (159, 'LAURA', 'BRODY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (160, 'CHRIS', 'DEPP', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (161, 'HARVEY', 'HOPE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (162, 'OPRAH', 'KILMER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (163, 'CHRISTOPHER', 'WEST', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (164, 'HUMPHREY', 'WILLIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (165, 'AL', 'GARLAND', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (166, 'NICK', 'DEGENERES', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (167, 'LAURENCE', 'BULLOCK', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (168, 'WILL', 'WILSON', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (169, 'KENNETH', 'HOFFMAN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (170, 'MENA', 'HOPPER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (171, 'OLYMPIA', 'PFEIFFER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (172, 'GROUCHO', 'WILLIAMS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (173, 'ALAN', 'DREYFUSS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (174, 'MICHAEL', 'BENING', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (175, 'WILLIAM', 'HACKMAN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (176, 'JON', 'CHASE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (177, 'GENE', 'MCKELLEN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (178, 'LISA', 'MONROE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (179, 'ED', 'GUINESS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (180, 'JEFF', 'SILVERSTONE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (181, 'MATTHEW', 'CARREY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (182, 'DEBBIE', 'AKROYD', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (183, 'RUSSELL', 'CLOSE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (184, 'HUMPHREY', 'GARLAND', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (185, 'MICHAEL', 'BOLGER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (186, 'JULIA', 'ZELLWEGER', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (187, 'RENEE', 'BALL', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (188, 'ROCK', 'DUKAKIS', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (189, 'CUBA', 'BIRCH', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (190, 'AUDREY', 'BAILEY', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (191, 'GREGORY', 'GOODING', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (192, 'JOHN', 'SUVARI', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (193, 'BURT', 'TEMPLE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (194, 'MERYL', 'ALLEN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (195, 'JAYNE', 'SILVERSTONE', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (196, 'BELA', 'WALKEN', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (197, 'REESE', 'WEST', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (198, 'MARY', 'KEITEL', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (199, 'JULIA', 'FAWCETT', '2017-02-15 09:34:33');
INSERT INTO actor VALUES (200, 'THORA', 'TEMPLE', '2017-02-15 09:34:33');


--
-- Data for Name: address; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: category; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO category VALUES (1, 'Action', '2017-02-15 09:46:27');
INSERT INTO category VALUES (2, 'Animation', '2017-02-15 09:46:27');
INSERT INTO category VALUES (3, 'Children', '2017-02-15 09:46:27');
INSERT INTO category VALUES (4, 'Classics', '2017-02-15 09:46:27');
INSERT INTO category VALUES (5, 'Comedy', '2017-02-15 09:46:27');
INSERT INTO category VALUES (6, 'Documentary', '2017-02-15 09:46:27');
INSERT INTO category VALUES (7, 'Drama', '2017-02-15 09:46:27');
INSERT INTO category VALUES (8, 'Family', '2017-02-15 09:46:27');
INSERT INTO category VALUES (9, 'Foreign', '2017-02-15 09:46:27');
INSERT INTO category VALUES (10, 'Games', '2017-02-15 09:46:27');
INSERT INTO category VALUES (11, 'Horror', '2017-02-15 09:46:27');
INSERT INTO category VALUES (12, 'Music', '2017-02-15 09:46:27');
INSERT INTO category VALUES (13, 'New', '2017-02-15 09:46:27');
INSERT INTO category VALUES (14, 'Sci-Fi', '2017-02-15 09:46:27');
INSERT INTO category VALUES (15, 'Sports', '2017-02-15 09:46:27');
INSERT INTO category VALUES (16, 'Travel', '2017-02-15 09:46:27');


--
-- Data for Name: city; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: country; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO country VALUES (1, 'Afghanistan', '2017-02-15 09:44:00');
INSERT INTO country VALUES (2, 'Algeria', '2017-02-15 09:44:00');
INSERT INTO country VALUES (3, 'American Samoa', '2017-02-15 09:44:00');
INSERT INTO country VALUES (4, 'Angola', '2017-02-15 09:44:00');
INSERT INTO country VALUES (5, 'Anguilla', '2017-02-15 09:44:00');
INSERT INTO country VALUES (6, 'Argentina', '2017-02-15 09:44:00');
INSERT INTO country VALUES (7, 'Armenia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (8, 'Australia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (9, 'Austria', '2017-02-15 09:44:00');
INSERT INTO country VALUES (10, 'Azerbaijan', '2017-02-15 09:44:00');
INSERT INTO country VALUES (11, 'Bahrain', '2017-02-15 09:44:00');
INSERT INTO country VALUES (12, 'Bangladesh', '2017-02-15 09:44:00');
INSERT INTO country VALUES (13, 'Belarus', '2017-02-15 09:44:00');
INSERT INTO country VALUES (14, 'Bolivia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (15, 'Brazil', '2017-02-15 09:44:00');
INSERT INTO country VALUES (16, 'Brunei', '2017-02-15 09:44:00');
INSERT INTO country VALUES (17, 'Bulgaria', '2017-02-15 09:44:00');
INSERT INTO country VALUES (18, 'Cambodia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (19, 'Cameroon', '2017-02-15 09:44:00');
INSERT INTO country VALUES (20, 'Canada', '2017-02-15 09:44:00');
INSERT INTO country VALUES (21, 'Chad', '2017-02-15 09:44:00');
INSERT INTO country VALUES (22, 'Chile', '2017-02-15 09:44:00');
INSERT INTO country VALUES (23, 'China', '2017-02-15 09:44:00');
INSERT INTO country VALUES (24, 'Colombia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (25, 'Congo, The Democratic Republic of the', '2017-02-15 09:44:00');
INSERT INTO country VALUES (26, 'Czech Republic', '2017-02-15 09:44:00');
INSERT INTO country VALUES (27, 'Dominican Republic', '2017-02-15 09:44:00');
INSERT INTO country VALUES (28, 'Ecuador', '2017-02-15 09:44:00');
INSERT INTO country VALUES (29, 'Egypt', '2017-02-15 09:44:00');
INSERT INTO country VALUES (30, 'Estonia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (31, 'Ethiopia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (32, 'Faroe Islands', '2017-02-15 09:44:00');
INSERT INTO country VALUES (33, 'Finland', '2017-02-15 09:44:00');
INSERT INTO country VALUES (34, 'France', '2017-02-15 09:44:00');
INSERT INTO country VALUES (35, 'French Guiana', '2017-02-15 09:44:00');
INSERT INTO country VALUES (36, 'French Polynesia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (37, 'Gambia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (38, 'Germany', '2017-02-15 09:44:00');
INSERT INTO country VALUES (39, 'Greece', '2017-02-15 09:44:00');
INSERT INTO country VALUES (40, 'Greenland', '2017-02-15 09:44:00');
INSERT INTO country VALUES (41, 'Holy See (Vatican City State)', '2017-02-15 09:44:00');
INSERT INTO country VALUES (42, 'Hong Kong', '2017-02-15 09:44:00');
INSERT INTO country VALUES (43, 'Hungary', '2017-02-15 09:44:00');
INSERT INTO country VALUES (44, 'India', '2017-02-15 09:44:00');
INSERT INTO country VALUES (45, 'Indonesia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (46, 'Iran', '2017-02-15 09:44:00');
INSERT INTO country VALUES (47, 'Iraq', '2017-02-15 09:44:00');
INSERT INTO country VALUES (48, 'Israel', '2017-02-15 09:44:00');
INSERT INTO country VALUES (49, 'Italy', '2017-02-15 09:44:00');
INSERT INTO country VALUES (50, 'Japan', '2017-02-15 09:44:00');
INSERT INTO country VALUES (51, 'Kazakstan', '2017-02-15 09:44:00');
INSERT INTO country VALUES (52, 'Kenya', '2017-02-15 09:44:00');
INSERT INTO country VALUES (53, 'Kuwait', '2017-02-15 09:44:00');
INSERT INTO country VALUES (54, 'Latvia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (55, 'Liechtenstein', '2017-02-15 09:44:00');
INSERT INTO country VALUES (56, 'Lithuania', '2017-02-15 09:44:00');
INSERT INTO country VALUES (57, 'Madagascar', '2017-02-15 09:44:00');
INSERT INTO country VALUES (58, 'Malawi', '2017-02-15 09:44:00');
INSERT INTO country VALUES (59, 'Malaysia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (60, 'Mexico', '2017-02-15 09:44:00');
INSERT INTO country VALUES (61, 'Moldova', '2017-02-15 09:44:00');
INSERT INTO country VALUES (62, 'Morocco', '2017-02-15 09:44:00');
INSERT INTO country VALUES (63, 'Mozambique', '2017-02-15 09:44:00');
INSERT INTO country VALUES (64, 'Myanmar', '2017-02-15 09:44:00');
INSERT INTO country VALUES (65, 'Nauru', '2017-02-15 09:44:00');
INSERT INTO country VALUES (66, 'Nepal', '2017-02-15 09:44:00');
INSERT INTO country VALUES (67, 'Netherlands', '2017-02-15 09:44:00');
INSERT INTO country VALUES (68, 'New Zealand', '2017-02-15 09:44:00');
INSERT INTO country VALUES (69, 'Nigeria', '2017-02-15 09:44:00');
INSERT INTO country VALUES (70, 'North Korea', '2017-02-15 09:44:00');
INSERT INTO country VALUES (71, 'Oman', '2017-02-15 09:44:00');
INSERT INTO country VALUES (72, 'Pakistan', '2017-02-15 09:44:00');
INSERT INTO country VALUES (73, 'Paraguay', '2017-02-15 09:44:00');
INSERT INTO country VALUES (74, 'Peru', '2017-02-15 09:44:00');
INSERT INTO country VALUES (75, 'Philippines', '2017-02-15 09:44:00');
INSERT INTO country VALUES (76, 'Poland', '2017-02-15 09:44:00');
INSERT INTO country VALUES (77, 'Puerto Rico', '2017-02-15 09:44:00');
INSERT INTO country VALUES (78, 'Romania', '2017-02-15 09:44:00');
INSERT INTO country VALUES (79, 'Runion', '2017-02-15 09:44:00');
INSERT INTO country VALUES (80, 'Russian Federation', '2017-02-15 09:44:00');
INSERT INTO country VALUES (81, 'Saint Vincent and the Grenadines', '2017-02-15 09:44:00');
INSERT INTO country VALUES (82, 'Saudi Arabia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (83, 'Senegal', '2017-02-15 09:44:00');
INSERT INTO country VALUES (84, 'Slovakia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (85, 'South Africa', '2017-02-15 09:44:00');
INSERT INTO country VALUES (86, 'South Korea', '2017-02-15 09:44:00');
INSERT INTO country VALUES (87, 'Spain', '2017-02-15 09:44:00');
INSERT INTO country VALUES (88, 'Sri Lanka', '2017-02-15 09:44:00');
INSERT INTO country VALUES (89, 'Sudan', '2017-02-15 09:44:00');
INSERT INTO country VALUES (90, 'Sweden', '2017-02-15 09:44:00');
INSERT INTO country VALUES (91, 'Switzerland', '2017-02-15 09:44:00');
INSERT INTO country VALUES (92, 'Taiwan', '2017-02-15 09:44:00');
INSERT INTO country VALUES (93, 'Tanzania', '2017-02-15 09:44:00');
INSERT INTO country VALUES (94, 'Thailand', '2017-02-15 09:44:00');
INSERT INTO country VALUES (95, 'Tonga', '2017-02-15 09:44:00');
INSERT INTO country VALUES (96, 'Tunisia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (97, 'Turkey', '2017-02-15 09:44:00');
INSERT INTO country VALUES (98, 'Turkmenistan', '2017-02-15 09:44:00');
INSERT INTO country VALUES (99, 'Tuvalu', '2017-02-15 09:44:00');
INSERT INTO country VALUES (100, 'Ukraine', '2017-02-15 09:44:00');
INSERT INTO country VALUES (101, 'United Arab Emirates', '2017-02-15 09:44:00');
INSERT INTO country VALUES (102, 'United Kingdom', '2017-02-15 09:44:00');
INSERT INTO country VALUES (103, 'United States', '2017-02-15 09:44:00');
INSERT INTO country VALUES (104, 'Venezuela', '2017-02-15 09:44:00');
INSERT INTO country VALUES (105, 'Vietnam', '2017-02-15 09:44:00');
INSERT INTO country VALUES (106, 'Virgin Islands, U.S.', '2017-02-15 09:44:00');
INSERT INTO country VALUES (107, 'Yemen', '2017-02-15 09:44:00');
INSERT INTO country VALUES (108, 'Yugoslavia', '2017-02-15 09:44:00');
INSERT INTO country VALUES (109, 'Zambia', '2017-02-15 09:44:00');


--
-- Data for Name: customer; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: film; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: film_actor; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: film_category; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: inventory; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: language; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO language VALUES (1, 'English             ', '2017-06-16 21:33:37.714126');
INSERT INTO language VALUES (2, 'Italian             ', '2017-06-16 21:33:37.714126');
INSERT INTO language VALUES (3, 'Japanese            ', '2017-06-16 21:33:37.714126');
INSERT INTO language VALUES (4, 'Mandarin            ', '2017-06-16 21:33:37.714126');
INSERT INTO language VALUES (5, 'French              ', '2017-06-16 21:33:37.714126');
INSERT INTO language VALUES (6, 'German              ', '2017-06-16 21:33:37.714126');


--
-- Data for Name: payment; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: payment_p2017_01; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: payment_p2017_02; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: payment_p2017_03; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: payment_p2017_04; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: payment_p2017_05; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: payment_p2017_06; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: rental; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: staff; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: store; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Name: actor_actor_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('actor_actor_id_seq', 200, true);


--
-- Name: address_address_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('address_address_id_seq', 605, true);


--
-- Name: category_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('category_category_id_seq', 16, true);


--
-- Name: city_city_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('city_city_id_seq', 600, true);


--
-- Name: country_country_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('country_country_id_seq', 109, true);


--
-- Name: customer_customer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('customer_customer_id_seq', 599, true);


--
-- Name: film_film_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('film_film_id_seq', 1000, true);


--
-- Name: inventory_inventory_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('inventory_inventory_id_seq', 4581, true);


--
-- Name: language_language_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('language_language_id_seq', 6, true);


--
-- Name: payment_payment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('payment_payment_id_seq', 32098, true);


--
-- Name: rental_rental_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('rental_rental_id_seq', 16049, true);


--
-- Name: staff_staff_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('staff_staff_id_seq', 2, true);


--
-- Name: store_store_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('store_store_id_seq', 2, true);


--
-- Name: actor actor_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY actor
    ADD CONSTRAINT actor_pkey PRIMARY KEY (actor_id);


--
-- Name: address address_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY address
    ADD CONSTRAINT address_pkey PRIMARY KEY (address_id);


--
-- Name: category category_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY category
    ADD CONSTRAINT category_pkey PRIMARY KEY (category_id);


--
-- Name: city city_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY city
    ADD CONSTRAINT city_pkey PRIMARY KEY (city_id);


--
-- Name: country country_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY country
    ADD CONSTRAINT country_pkey PRIMARY KEY (country_id);


--
-- Name: customer customer_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (customer_id);


--
-- Name: film_actor film_actor_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY film_actor
    ADD CONSTRAINT film_actor_pkey PRIMARY KEY (actor_id, film_id);


--
-- Name: film_category film_category_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY film_category
    ADD CONSTRAINT film_category_pkey PRIMARY KEY (film_id, category_id);


--
-- Name: film film_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY film
    ADD CONSTRAINT film_pkey PRIMARY KEY (film_id);


--
-- Name: inventory inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (inventory_id);


--
-- Name: language language_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY language
    ADD CONSTRAINT language_pkey PRIMARY KEY (language_id);


--
-- Name: payment payment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment
    ADD CONSTRAINT payment_pkey PRIMARY KEY (payment_id);


--
-- Name: rental rental_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rental
    ADD CONSTRAINT rental_pkey PRIMARY KEY (rental_id);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (staff_id);


--
-- Name: store store_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY store
    ADD CONSTRAINT store_pkey PRIMARY KEY (store_id);


--
-- Name: film_fulltext_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX film_fulltext_idx ON film USING gist (fulltext);


--
-- Name: idx_actor_last_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_actor_last_name ON actor USING btree (last_name);


--
-- Name: idx_fk_address_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_address_id ON customer USING btree (address_id);


--
-- Name: idx_fk_city_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_city_id ON address USING btree (city_id);


--
-- Name: idx_fk_country_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_country_id ON city USING btree (country_id);


--
-- Name: idx_fk_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_customer_id ON payment USING btree (customer_id);


--
-- Name: idx_fk_film_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_film_id ON film_actor USING btree (film_id);


--
-- Name: idx_fk_inventory_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_inventory_id ON rental USING btree (inventory_id);


--
-- Name: idx_fk_language_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_language_id ON film USING btree (language_id);


--
-- Name: idx_fk_original_language_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_original_language_id ON film USING btree (original_language_id);


--
-- Name: idx_fk_payment_p2017_01_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_01_customer_id ON payment_p2017_01 USING btree (customer_id);


--
-- Name: idx_fk_payment_p2017_01_staff_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_01_staff_id ON payment_p2017_01 USING btree (staff_id);


--
-- Name: idx_fk_payment_p2017_02_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_02_customer_id ON payment_p2017_02 USING btree (customer_id);


--
-- Name: idx_fk_payment_p2017_02_staff_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_02_staff_id ON payment_p2017_02 USING btree (staff_id);


--
-- Name: idx_fk_payment_p2017_03_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_03_customer_id ON payment_p2017_03 USING btree (customer_id);


--
-- Name: idx_fk_payment_p2017_03_staff_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_03_staff_id ON payment_p2017_03 USING btree (staff_id);


--
-- Name: idx_fk_payment_p2017_04_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_04_customer_id ON payment_p2017_04 USING btree (customer_id);


--
-- Name: idx_fk_payment_p2017_04_staff_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_04_staff_id ON payment_p2017_04 USING btree (staff_id);


--
-- Name: idx_fk_payment_p2017_05_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_05_customer_id ON payment_p2017_05 USING btree (customer_id);


--
-- Name: idx_fk_payment_p2017_05_staff_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_05_staff_id ON payment_p2017_05 USING btree (staff_id);


--
-- Name: idx_fk_payment_p2017_06_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_06_customer_id ON payment_p2017_06 USING btree (customer_id);


--
-- Name: idx_fk_payment_p2017_06_staff_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_payment_p2017_06_staff_id ON payment_p2017_06 USING btree (staff_id);


--
-- Name: idx_fk_staff_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_staff_id ON payment USING btree (staff_id);


--
-- Name: idx_fk_store_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fk_store_id ON customer USING btree (store_id);


--
-- Name: idx_last_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_last_name ON customer USING btree (last_name);


--
-- Name: idx_store_id_film_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_store_id_film_id ON inventory USING btree (store_id, film_id);


--
-- Name: idx_title; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_title ON film USING btree (title);


--
-- Name: idx_unq_manager_staff_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_unq_manager_staff_id ON store USING btree (manager_staff_id);


--
-- Name: idx_unq_rental_rental_date_inventory_id_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_unq_rental_rental_date_inventory_id_customer_id ON rental USING btree (rental_date, inventory_id, customer_id);


--
-- Name: film film_fulltext_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER film_fulltext_trigger BEFORE INSERT OR UPDATE ON film FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger('fulltext', 'pg_catalog.english', 'title', 'description');


--
-- Name: actor last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON actor FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: address last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON address FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: category last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON category FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: city last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON city FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: country last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON country FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: customer last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON customer FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: film last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON film FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: film_actor last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON film_actor FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: film_category last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON film_category FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: inventory last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON inventory FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: language last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON language FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: rental last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON rental FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: staff last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON staff FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: store last_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER last_updated BEFORE UPDATE ON store FOR EACH ROW EXECUTE PROCEDURE last_updated();


--
-- Name: payment pagila_payment_insert_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER pagila_payment_insert_trigger BEFORE INSERT ON payment FOR EACH ROW EXECUTE PROCEDURE pagila_payment_insert_trigger();


--
-- Name: address address_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY address
    ADD CONSTRAINT address_city_id_fkey FOREIGN KEY (city_id) REFERENCES city(city_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: city city_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY city
    ADD CONSTRAINT city_country_id_fkey FOREIGN KEY (country_id) REFERENCES country(country_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: customer customer_address_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY customer
    ADD CONSTRAINT customer_address_id_fkey FOREIGN KEY (address_id) REFERENCES address(address_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: customer customer_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY customer
    ADD CONSTRAINT customer_store_id_fkey FOREIGN KEY (store_id) REFERENCES store(store_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: film_actor film_actor_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY film_actor
    ADD CONSTRAINT film_actor_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES actor(actor_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: film_actor film_actor_film_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY film_actor
    ADD CONSTRAINT film_actor_film_id_fkey FOREIGN KEY (film_id) REFERENCES film(film_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: film_category film_category_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY film_category
    ADD CONSTRAINT film_category_category_id_fkey FOREIGN KEY (category_id) REFERENCES category(category_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: film_category film_category_film_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY film_category
    ADD CONSTRAINT film_category_film_id_fkey FOREIGN KEY (film_id) REFERENCES film(film_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: film film_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY film
    ADD CONSTRAINT film_language_id_fkey FOREIGN KEY (language_id) REFERENCES language(language_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: film film_original_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY film
    ADD CONSTRAINT film_original_language_id_fkey FOREIGN KEY (original_language_id) REFERENCES language(language_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: inventory inventory_film_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY inventory
    ADD CONSTRAINT inventory_film_id_fkey FOREIGN KEY (film_id) REFERENCES film(film_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: inventory inventory_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY inventory
    ADD CONSTRAINT inventory_store_id_fkey FOREIGN KEY (store_id) REFERENCES store(store_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: payment payment_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment
    ADD CONSTRAINT payment_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: payment_p2017_01 payment_p2017_01_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_01
    ADD CONSTRAINT payment_p2017_01_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customer(customer_id);


--
-- Name: payment_p2017_01 payment_p2017_01_rental_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_01
    ADD CONSTRAINT payment_p2017_01_rental_id_fkey FOREIGN KEY (rental_id) REFERENCES rental(rental_id);


--
-- Name: payment_p2017_01 payment_p2017_01_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_01
    ADD CONSTRAINT payment_p2017_01_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES staff(staff_id);


--
-- Name: payment_p2017_02 payment_p2017_02_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_02
    ADD CONSTRAINT payment_p2017_02_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customer(customer_id);


--
-- Name: payment_p2017_02 payment_p2017_02_rental_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_02
    ADD CONSTRAINT payment_p2017_02_rental_id_fkey FOREIGN KEY (rental_id) REFERENCES rental(rental_id);


--
-- Name: payment_p2017_02 payment_p2017_02_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_02
    ADD CONSTRAINT payment_p2017_02_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES staff(staff_id);


--
-- Name: payment_p2017_03 payment_p2017_03_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_03
    ADD CONSTRAINT payment_p2017_03_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customer(customer_id);


--
-- Name: payment_p2017_03 payment_p2017_03_rental_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_03
    ADD CONSTRAINT payment_p2017_03_rental_id_fkey FOREIGN KEY (rental_id) REFERENCES rental(rental_id);


--
-- Name: payment_p2017_03 payment_p2017_03_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_03
    ADD CONSTRAINT payment_p2017_03_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES staff(staff_id);


--
-- Name: payment_p2017_04 payment_p2017_04_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_04
    ADD CONSTRAINT payment_p2017_04_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customer(customer_id);


--
-- Name: payment_p2017_04 payment_p2017_04_rental_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_04
    ADD CONSTRAINT payment_p2017_04_rental_id_fkey FOREIGN KEY (rental_id) REFERENCES rental(rental_id);


--
-- Name: payment_p2017_04 payment_p2017_04_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_04
    ADD CONSTRAINT payment_p2017_04_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES staff(staff_id);


--
-- Name: payment_p2017_05 payment_p2017_05_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_05
    ADD CONSTRAINT payment_p2017_05_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customer(customer_id);


--
-- Name: payment_p2017_05 payment_p2017_05_rental_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_05
    ADD CONSTRAINT payment_p2017_05_rental_id_fkey FOREIGN KEY (rental_id) REFERENCES rental(rental_id);


--
-- Name: payment_p2017_05 payment_p2017_05_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_05
    ADD CONSTRAINT payment_p2017_05_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES staff(staff_id);


--
-- Name: payment_p2017_06 payment_p2017_06_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_06
    ADD CONSTRAINT payment_p2017_06_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customer(customer_id);


--
-- Name: payment_p2017_06 payment_p2017_06_rental_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_06
    ADD CONSTRAINT payment_p2017_06_rental_id_fkey FOREIGN KEY (rental_id) REFERENCES rental(rental_id);


--
-- Name: payment_p2017_06 payment_p2017_06_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment_p2017_06
    ADD CONSTRAINT payment_p2017_06_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES staff(staff_id);


--
-- Name: payment payment_rental_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment
    ADD CONSTRAINT payment_rental_id_fkey FOREIGN KEY (rental_id) REFERENCES rental(rental_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: payment payment_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY payment
    ADD CONSTRAINT payment_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES staff(staff_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: rental rental_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rental
    ADD CONSTRAINT rental_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: rental rental_inventory_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rental
    ADD CONSTRAINT rental_inventory_id_fkey FOREIGN KEY (inventory_id) REFERENCES inventory(inventory_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: rental rental_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rental
    ADD CONSTRAINT rental_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES staff(staff_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: staff staff_address_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY staff
    ADD CONSTRAINT staff_address_id_fkey FOREIGN KEY (address_id) REFERENCES address(address_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: staff staff_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY staff
    ADD CONSTRAINT staff_store_id_fkey FOREIGN KEY (store_id) REFERENCES store(store_id);


--
-- Name: store store_address_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY store
    ADD CONSTRAINT store_address_id_fkey FOREIGN KEY (address_id) REFERENCES address(address_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: store store_manager_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY store
    ADD CONSTRAINT store_manager_staff_id_fkey FOREIGN KEY (manager_staff_id) REFERENCES staff(staff_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

