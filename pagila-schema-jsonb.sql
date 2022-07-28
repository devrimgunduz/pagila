--
-- PostgreSQL database dump
--

-- Dumped from database version 12.11
-- Dumped by pg_dump version 15beta2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: packages_apt_postgresql_org; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.packages_apt_postgresql_org (
    id integer NOT NULL,
    last_updated timestamp without time zone DEFAULT now(),
    aptdata jsonb
);


ALTER TABLE public.packages_apt_postgresql_org OWNER TO postgres;

--
-- Name: newaptdata_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.packages_apt_postgresql_org ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.newaptdata_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: packages_yum_postgresql_org; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.packages_yum_postgresql_org (
    id integer NOT NULL,
    last_updated timestamp without time zone DEFAULT now(),
    yumdata jsonb
);


ALTER TABLE public.packages_yum_postgresql_org OWNER TO postgres;

--
-- Name: newyumdata_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.packages_yum_postgresql_org ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.newyumdata_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- PostgreSQL database dump complete
--

