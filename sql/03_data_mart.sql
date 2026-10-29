-- =====================================================================
-- 03_data_mart.sql
-- Data mart departamental (esquema estrella) derivado del EDW `dwh`.
-- Es el que consume Power BI. Son vistas: siempre reflejan el EDW.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS mart;

CREATE OR REPLACE VIEW mart.dim_plataforma AS
SELECT plataforma_id, nombre AS plataforma, empresa
FROM dwh.plataforma;

CREATE OR REPLACE VIEW mart.dim_clasificacion AS
SELECT DISTINCT
    m.grupo_edad,
    m.orden AS orden_grupo
FROM dwh.map_clasificacion m;

-- Eje temporal común: año de estreno. La fecha de alta en la plataforma no
-- sirve para comparar porque Prime Video la informa en menos del 2 % de los títulos.
CREATE OR REPLACE VIEW mart.dim_anio AS
SELECT
    a                                  AS anio,
    (a / 10 * 10)::text || 's'         AS decada,
    CASE WHEN a < 2000 THEN 'Antes de 2000'
         WHEN a < 2010 THEN '2000-2009'
         WHEN a < 2015 THEN '2010-2014'
         ELSE '2015-2021' END          AS periodo
FROM generate_series(1920, 2021) AS a;

CREATE OR REPLACE VIEW mart.fact_titulo AS
SELECT
    t.titulo_id,
    t.plataforma_id,
    t.show_id,
    t.titulo,
    t.tipo,
    t.clasificacion_original,
    COALESCE(m.grupo_edad, 'Sin clasificar') AS grupo_edad,
    t.anio_estreno,
    t.fecha_agregado,
    t.duracion_min,
    t.temporadas,
    1                                        AS cantidad
FROM dwh.titulo t
LEFT JOIN dwh.map_clasificacion m ON m.clasificacion_original = t.clasificacion_original;

CREATE OR REPLACE VIEW mart.bridge_titulo_genero AS
SELECT DISTINCT tg.titulo_id, COALESCE(m.genero_unificado, 'Otros') AS genero
FROM dwh.titulo_genero tg
LEFT JOIN dwh.map_genero m ON m.genero_original = tg.genero_original;

CREATE OR REPLACE VIEW mart.dim_genero AS
SELECT DISTINCT genero FROM mart.bridge_titulo_genero;

CREATE OR REPLACE VIEW mart.bridge_titulo_pais AS
SELECT titulo_id, pais FROM dwh.titulo_pais;

CREATE OR REPLACE VIEW mart.dim_pais AS
SELECT DISTINCT pais FROM dwh.titulo_pais;

-- Calidad de datos por fuente (sustenta la comparación)
CREATE OR REPLACE VIEW mart.calidad_fuente AS
SELECT
    p.nombre                                                      AS plataforma,
    count(*)                                                      AS titulos,
    round(100.0 * count(*) FILTER (WHERE t.fecha_agregado IS NULL) / count(*), 1)          AS pct_sin_fecha_alta,
    round(100.0 * count(*) FILTER (WHERE NOT EXISTS
        (SELECT 1 FROM dwh.titulo_pais tp WHERE tp.titulo_id = t.titulo_id)) / count(*), 1) AS pct_sin_pais,
    round(100.0 * count(*) FILTER (WHERE t.director = 'Sin dato') / count(*), 1)            AS pct_sin_director,
    round(100.0 * count(*) FILTER (WHERE t.clasificacion_original = 'Sin dato') / count(*), 1) AS pct_sin_clasificacion
FROM dwh.titulo t
JOIN dwh.plataforma p USING (plataforma_id)
GROUP BY p.nombre;
