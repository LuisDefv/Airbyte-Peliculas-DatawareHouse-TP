--
-- PostgreSQL database dump
--

\restrict 1TdVcTXhjG8lKXfdVyyppb9xoNJ5Y015fsoi7twgk56Sx7yQe10lb7Sl8AtaF7n

-- Dumped from database version 16.14 (Debian 16.14-1.pgdg13+1)
-- Dumped by pg_dump version 16.14 (Debian 16.14-1.pgdg13+1)

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

--
-- Name: dw; Type: SCHEMA; Schema: -; Owner: netflix
--

CREATE SCHEMA dw;


ALTER SCHEMA dw OWNER TO netflix;

--
-- Name: bridge_titulo_genero; Type: VIEW; Schema: dw; Owner: netflix
--

CREATE VIEW dw.bridge_titulo_genero AS
 SELECT DISTINCT netflix_titles.show_id,
    TRIM(BOTH FROM g.g) AS genero
   FROM raw.netflix_titles,
    LATERAL unnest(string_to_array((netflix_titles.listed_in)::text, ','::text)) g(g)
  WHERE (TRIM(BOTH FROM g.g) <> ''::text);


ALTER VIEW dw.bridge_titulo_genero OWNER TO netflix;

--
-- Name: bridge_titulo_pais; Type: VIEW; Schema: dw; Owner: netflix
--

CREATE VIEW dw.bridge_titulo_pais AS
 SELECT DISTINCT netflix_titles.show_id,
    TRIM(BOTH FROM p.p) AS pais
   FROM raw.netflix_titles,
    LATERAL unnest(string_to_array((netflix_titles.country)::text, ','::text)) p(p)
  WHERE (TRIM(BOTH FROM p.p) <> ''::text);


ALTER VIEW dw.bridge_titulo_pais OWNER TO netflix;

--
-- Name: fact_titulos; Type: VIEW; Schema: dw; Owner: netflix
--

CREATE VIEW dw.fact_titulos AS
 WITH base AS (
         SELECT netflix_titles.show_id,
            netflix_titles.title,
            netflix_titles.type,
                CASE
                    WHEN ((netflix_titles.rating)::text ~~ '% min'::text) THEN NULL::character varying
                    ELSE netflix_titles.rating
                END AS rating,
            COALESCE(netflix_titles.duration,
                CASE
                    WHEN ((netflix_titles.rating)::text ~~ '% min'::text) THEN netflix_titles.rating
                    ELSE NULL::character varying
                END) AS duration,
            netflix_titles.director,
            (netflix_titles.release_year)::integer AS release_year,
            to_date(NULLIF(TRIM(BOTH FROM netflix_titles.date_added), ''::text), 'Month DD, YYYY'::text) AS date_added,
            netflix_titles.description
           FROM raw.netflix_titles
        )
 SELECT show_id,
    title AS titulo,
        CASE type
            WHEN 'Movie'::text THEN 'Película'::text
            ELSE 'Serie'::text
        END AS tipo,
    COALESCE(rating, 'Sin dato'::character varying) AS clasificacion,
    COALESCE(director, 'Sin dato'::character varying) AS director,
    release_year AS anio_estreno,
    date_added AS fecha_agregado,
    (to_char((date_added)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS fecha_key,
        CASE
            WHEN ((duration)::text ~~ '% min'::text) THEN (split_part((duration)::text, ' '::text, 1))::integer
            ELSE NULL::integer
        END AS duracion_min,
        CASE
            WHEN ((duration)::text ~~ '% Season%'::text) THEN (split_part((duration)::text, ' '::text, 1))::integer
            ELSE NULL::integer
        END AS temporadas,
    ((date_part('year'::text, date_added))::integer - release_year) AS anios_hasta_netflix,
    description AS descripcion,
    1 AS cantidad
   FROM base;


ALTER VIEW dw.fact_titulos OWNER TO netflix;

--
-- Name: dim_fecha; Type: VIEW; Schema: dw; Owner: netflix
--

CREATE VIEW dw.dim_fecha AS
 SELECT DISTINCT (to_char((d)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS fecha_key,
    d AS fecha,
    (EXTRACT(year FROM d))::integer AS anio,
    (EXTRACT(quarter FROM d))::integer AS trimestre,
    (EXTRACT(month FROM d))::integer AS mes,
        CASE (EXTRACT(month FROM d))::integer
            WHEN 1 THEN 'Enero'::text
            WHEN 2 THEN 'Febrero'::text
            WHEN 3 THEN 'Marzo'::text
            WHEN 4 THEN 'Abril'::text
            WHEN 5 THEN 'Mayo'::text
            WHEN 6 THEN 'Junio'::text
            WHEN 7 THEN 'Julio'::text
            WHEN 8 THEN 'Agosto'::text
            WHEN 9 THEN 'Septiembre'::text
            WHEN 10 THEN 'Octubre'::text
            WHEN 11 THEN 'Noviembre'::text
            ELSE 'Diciembre'::text
        END AS nombre_mes
   FROM ( SELECT fact_titulos.fecha_agregado AS d
           FROM dw.fact_titulos
          WHERE (fact_titulos.fecha_agregado IS NOT NULL)) f;


ALTER VIEW dw.dim_fecha OWNER TO netflix;

--
-- Name: dim_genero; Type: VIEW; Schema: dw; Owner: netflix
--

CREATE VIEW dw.dim_genero AS
 SELECT DISTINCT genero
   FROM dw.bridge_titulo_genero;


ALTER VIEW dw.dim_genero OWNER TO netflix;

--
-- Name: dim_pais; Type: VIEW; Schema: dw; Owner: netflix
--

CREATE VIEW dw.dim_pais AS
 SELECT DISTINCT pais
   FROM dw.bridge_titulo_pais;


ALTER VIEW dw.dim_pais OWNER TO netflix;

--
-- PostgreSQL database dump complete
--

\unrestrict 1TdVcTXhjG8lKXfdVyyppb9xoNJ5Y015fsoi7twgk56Sx7yQe10lb7Sl8AtaF7n

