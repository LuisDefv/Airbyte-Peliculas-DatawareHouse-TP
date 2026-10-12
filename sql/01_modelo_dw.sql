-- Modelo estrella sobre la tabla cruda que carga Airbyte (raw.netflix_titles).
-- Son vistas: cada sync de Airbyte actualiza el DW solo, sin reprocesar nada.

CREATE SCHEMA IF NOT EXISTS dw;

-- Tabla de hechos: un registro por título
CREATE OR REPLACE VIEW dw.fact_titulos AS
WITH base AS (
    SELECT
        show_id,
        title,
        type,
        -- en el dataset hay 3 filas con la duración cargada en "rating"
        CASE WHEN rating LIKE '% min' THEN NULL ELSE rating END           AS rating,
        COALESCE(duration, CASE WHEN rating LIKE '% min' THEN rating END) AS duration,
        director,
        release_year::int                                                 AS release_year,
        to_date(NULLIF(trim(date_added), ''), 'Month DD, YYYY')          AS date_added,
        description
    FROM raw.netflix_titles
)
SELECT
    show_id,
    title                                                   AS titulo,
    CASE type WHEN 'Movie' THEN 'Película' ELSE 'Serie' END AS tipo,
    COALESCE(rating, 'Sin dato')                            AS clasificacion,
    COALESCE(director, 'Sin dato')                          AS director,
    release_year                                            AS anio_estreno,
    date_added                                              AS fecha_agregado,
    to_char(date_added, 'YYYYMMDD')::int                    AS fecha_key,
    CASE WHEN duration LIKE '% min'    THEN split_part(duration, ' ', 1)::int END AS duracion_min,
    CASE WHEN duration LIKE '% Season%' THEN split_part(duration, ' ', 1)::int END AS temporadas,
    date_part('year', date_added)::int - release_year       AS anios_hasta_netflix,
    description                                             AS descripcion,
    1                                                       AS cantidad
FROM base;

-- Dimensión fecha (fecha en que se agregó a Netflix)
CREATE OR REPLACE VIEW dw.dim_fecha AS
SELECT DISTINCT
    to_char(d, 'YYYYMMDD')::int  AS fecha_key,
    d                            AS fecha,
    extract(year FROM d)::int    AS anio,
    extract(quarter FROM d)::int AS trimestre,
    extract(month FROM d)::int   AS mes,
    CASE extract(month FROM d)::int
        WHEN 1 THEN 'Enero'  WHEN 2 THEN 'Febrero' WHEN 3 THEN 'Marzo'
        WHEN 4 THEN 'Abril'  WHEN 5 THEN 'Mayo'    WHEN 6 THEN 'Junio'
        WHEN 7 THEN 'Julio'  WHEN 8 THEN 'Agosto'  WHEN 9 THEN 'Septiembre'
        WHEN 10 THEN 'Octubre' WHEN 11 THEN 'Noviembre' ELSE 'Diciembre'
    END                          AS nombre_mes
FROM (SELECT fecha_agregado AS d FROM dw.fact_titulos WHERE fecha_agregado IS NOT NULL) f;

-- Géneros (un título tiene varios -> tabla puente)
CREATE OR REPLACE VIEW dw.bridge_titulo_genero AS
SELECT DISTINCT show_id, trim(g) AS genero
FROM raw.netflix_titles, unnest(string_to_array(listed_in, ',')) AS g
WHERE trim(g) <> '';

CREATE OR REPLACE VIEW dw.dim_genero AS
SELECT DISTINCT genero FROM dw.bridge_titulo_genero;

-- Países (un título tiene varios -> tabla puente)
CREATE OR REPLACE VIEW dw.bridge_titulo_pais AS
SELECT DISTINCT show_id, trim(p) AS pais
FROM raw.netflix_titles, unnest(string_to_array(country, ',')) AS p
WHERE trim(p) <> '';

CREATE OR REPLACE VIEW dw.dim_pais AS
SELECT DISTINCT pais FROM dw.bridge_titulo_pais;
