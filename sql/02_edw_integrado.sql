-- =====================================================================
-- 02_edw_integrado.sql
-- Data Warehouse corporativo (EDW) integrado, según Inmon:
--   raw  -> staging que escribe Airbyte (volátil: Full refresh | Overwrite)
--   dwh  -> datos integrados, no volátiles y variantes en el tiempo
--   mart -> data mart dimensional para el tablero (03_data_mart.sql)
--
-- Ejecutar una vez para crear la estructura y luego, después de cada
-- sincronización de Airbyte:   CALL dwh.sp_cargar_dwh();
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS dwh;

-- ---------------------------------------------------------------------
-- Tablas de referencia (integración: un único código para todo el DW)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dwh.plataforma (
    plataforma_id smallint PRIMARY KEY,
    nombre        text NOT NULL UNIQUE,
    empresa       text NOT NULL,
    url_fuente    text NOT NULL
);

INSERT INTO dwh.plataforma VALUES
 (1, 'Netflix',     'Netflix, Inc.',
  'https://raw.githubusercontent.com/LuisDefv/Airbyte-Peliculas-DatawareHouse-TP/main/netflix_titles.csv'),
 (2, 'Prime Video', 'Amazon.com, Inc.',
  'https://raw.githubusercontent.com/LuisDefv/Airbyte-Peliculas-DatawareHouse-TP/main/amazon_prime_titles.csv')
ON CONFLICT (plataforma_id) DO NOTHING;

-- Cada plataforma usa su propio sistema de calificación por edad
-- (Netflix: TV-MA, TV-14...; Prime Video: 18+, 13+, ALL...).
-- Se homologan a un grupo de edad común.
CREATE TABLE IF NOT EXISTS dwh.map_clasificacion (
    clasificacion_original text PRIMARY KEY,
    grupo_edad             text NOT NULL,
    orden                  smallint NOT NULL
);

INSERT INTO dwh.map_clasificacion VALUES
 ('TV-Y','Infantil',1), ('TV-Y7','Infantil',1), ('TV-Y7-FV','Infantil',1),
 ('G','Infantil',1), ('TV-G','Infantil',1), ('ALL','Infantil',1),
 ('ALL_AGES','Infantil',1), ('7+','Infantil',1),
 ('PG','Familiar (guía parental)',2), ('TV-PG','Familiar (guía parental)',2),
 ('PG-13','Adolescentes (13+)',3), ('TV-14','Adolescentes (13+)',3), ('13+','Adolescentes (13+)',3),
 ('16+','Adultos (16+)',4), ('16','Adultos (16+)',4), ('AGES_16_','Adultos (16+)',4),
 ('18+','Adultos (16+)',4), ('AGES_18_','Adultos (16+)',4), ('R','Adultos (16+)',4),
 ('NC-17','Adultos (16+)',4), ('TV-MA','Adultos (16+)',4),
 ('NR','Sin clasificar',5), ('UR','Sin clasificar',5), ('UNRATED','Sin clasificar',5),
 ('NOT_RATE','Sin clasificar',5), ('TV-NR','Sin clasificar',5), ('Sin dato','Sin clasificar',5)
ON CONFLICT (clasificacion_original) DO NOTHING;

-- Los géneros también vienen con nombres distintos
-- (Netflix "Dramas"/"TV Dramas", Prime Video "Drama"): se unifican.
CREATE TABLE IF NOT EXISTS dwh.map_genero (
    genero_original  text PRIMARY KEY,
    genero_unificado text NOT NULL
);

INSERT INTO dwh.map_genero VALUES
 -- Netflix
 ('Action & Adventure','Acción y aventura'), ('TV Action & Adventure','Acción y aventura'),
 ('Anime Features','Animación y anime'), ('Anime Series','Animación y anime'),
 ('British TV Shows','Internacional'), ('International Movies','Internacional'),
 ('International TV Shows','Internacional'), ('Korean TV Shows','Internacional'),
 ('Spanish-Language TV Shows','Internacional'),
 ('Children & Family Movies','Infantil y familiar'), ('Kids'' TV','Infantil y familiar'),
 ('Classic & Cult TV','Clásicos y de culto'), ('Classic Movies','Clásicos y de culto'),
 ('Cult Movies','Clásicos y de culto'),
 ('Comedies','Comedia'), ('TV Comedies','Comedia'),
 ('Stand-Up Comedy','Stand-up y variedades'), ('Stand-Up Comedy & Talk Shows','Stand-up y variedades'),
 ('Crime TV Shows','Suspenso y policial'), ('Thrillers','Suspenso y policial'),
 ('TV Thrillers','Suspenso y policial'), ('TV Mysteries','Suspenso y policial'),
 ('Documentaries','Documental'), ('Docuseries','Documental'), ('Science & Nature TV','Documental'),
 ('Dramas','Drama'), ('TV Dramas','Drama'),
 ('Faith & Spirituality','Fe y espiritualidad'),
 ('Horror Movies','Terror'), ('TV Horror','Terror'),
 ('Independent Movies','Independiente y arthouse'),
 ('LGBTQ Movies','LGBTQ'),
 ('Music & Musicals','Música'),
 ('Reality TV','Reality'),
 ('Romantic Movies','Romance'), ('Romantic TV Shows','Romance'),
 ('Sci-Fi & Fantasy','Ciencia ficción y fantasía'), ('TV Sci-Fi & Fantasy','Ciencia ficción y fantasía'),
 ('Sports Movies','Deportes y fitness'),
 ('Teen TV Shows','Juvenil'),
 ('Movies','Sin género específico'), ('TV Shows','Sin género específico'),
 -- Prime Video
 ('Action','Acción y aventura'), ('Adventure','Acción y aventura'),
 ('Animation','Animación y anime'), ('Anime','Animación y anime'),
 ('Arthouse','Independiente y arthouse'),
 ('Arts, Entertainment, and Culture','Arte y cultura'),
 ('Comedy','Comedia'), ('Talk Show and Variety','Stand-up y variedades'),
 ('Documentary','Documental'), ('Special Interest','Documental'),
 ('Drama','Drama'),
 ('Faith and Spirituality','Fe y espiritualidad'),
 ('Fantasy','Ciencia ficción y fantasía'), ('Science Fiction','Ciencia ficción y fantasía'),
 ('Fitness','Deportes y fitness'), ('Sports','Deportes y fitness'),
 ('Historical','Bélico e histórico'), ('Military and War','Bélico e histórico'),
 ('Horror','Terror'),
 ('International','Internacional'),
 ('Kids','Infantil y familiar'),
 ('LGBTQ','LGBTQ'),
 ('Music Videos and Concerts','Música'),
 ('Romance','Romance'),
 ('Suspense','Suspenso y policial'),
 ('Unscripted','Reality'),
 ('Western','Western'),
 ('Young Adult Audience','Juvenil')
ON CONFLICT (genero_original) DO NOTHING;

-- ---------------------------------------------------------------------
-- Control de cargas: bitácora append-only (variación en el tiempo)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dwh.control_carga (
    carga_id           serial PRIMARY KEY,
    fecha_carga        timestamptz NOT NULL DEFAULT now(),
    plataforma_id      smallint NOT NULL REFERENCES dwh.plataforma,
    filas_staging      int NOT NULL,
    filas_nuevas       int NOT NULL,
    filas_actualizadas int NOT NULL
);

-- ---------------------------------------------------------------------
-- Entidad central integrada: un registro por título y plataforma
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dwh.titulo (
    titulo_id              serial PRIMARY KEY,
    plataforma_id          smallint NOT NULL REFERENCES dwh.plataforma,
    show_id                text NOT NULL,          -- clave natural de la fuente
    titulo                 text NOT NULL,
    tipo                   text NOT NULL,          -- 'Película' | 'Serie'
    clasificacion_original text NOT NULL,
    director               text NOT NULL,
    anio_estreno           smallint,
    fecha_agregado         date,                   -- casi siempre nula en Prime Video
    duracion_min           smallint,               -- solo películas
    temporadas             smallint,               -- solo series
    descripcion            text,
    carga_id_alta          int NOT NULL REFERENCES dwh.control_carga,
    carga_id_ultima        int NOT NULL REFERENCES dwh.control_carga,
    fecha_alta             timestamptz NOT NULL DEFAULT now(),
    fecha_ultima_vista     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (plataforma_id, show_id)
);

CREATE TABLE IF NOT EXISTS dwh.titulo_genero (
    titulo_id       int  NOT NULL REFERENCES dwh.titulo,
    genero_original text NOT NULL,
    PRIMARY KEY (titulo_id, genero_original)
);

CREATE TABLE IF NOT EXISTS dwh.titulo_pais (
    titulo_id int  NOT NULL REFERENCES dwh.titulo,
    pais      text NOT NULL,
    PRIMARY KEY (titulo_id, pais)
);

-- ---------------------------------------------------------------------
-- Staging unificado: lleva ambas fuentes al mismo formato.
-- IMPORTANTE: no puede ser una vista sobre `raw`. Con "Full refresh |
-- Overwrite" Airbyte borra y recrea las tablas de `raw` en cada sync, y
-- PostgreSQL no permite borrar una tabla de la que depende una vista.
-- Por eso se materializa en una tabla temporal dentro del proceso de carga.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE dwh.sp_preparar_staging()
LANGUAGE plpgsql AS $$
BEGIN
DROP TABLE IF EXISTS tmp_staging;
CREATE TEMP TABLE tmp_staging AS
WITH fuentes AS (
    SELECT 1::smallint AS plataforma_id, show_id, type, title, director, country,
           date_added, release_year::text AS release_year, rating, duration, listed_in, description
    FROM raw.netflix_titles
    UNION ALL
    SELECT 2::smallint, show_id, type, title, director, country,
           date_added, release_year::text, rating, duration, listed_in, description
    FROM raw.amazon_prime_titles
), corregidas AS (
    SELECT *,
        -- Netflix tiene 3 filas con la duración cargada en "rating"
        CASE WHEN rating LIKE '% min' THEN NULL ELSE NULLIF(trim(rating), '') END            AS rating_ok,
        COALESCE(NULLIF(trim(duration), ''),
                 CASE WHEN rating LIKE '% min' THEN rating END)                              AS duration_ok
    FROM fuentes
)
SELECT
    plataforma_id,
    show_id,
    trim(title)                                                   AS titulo,
    CASE type WHEN 'Movie' THEN 'Película' ELSE 'Serie' END       AS tipo,
    COALESCE(rating_ok, 'Sin dato')                               AS clasificacion_original,
    COALESCE(NULLIF(trim(director), ''), 'Sin dato')              AS director,
    NULLIF(split_part(release_year, '.', 1), '')::smallint        AS anio_estreno,
    to_date(NULLIF(trim(date_added), ''), 'Month DD, YYYY')       AS fecha_agregado,
    CASE WHEN duration_ok LIKE '% min'     THEN split_part(duration_ok, ' ', 1)::smallint END AS duracion_min,
    CASE WHEN duration_ok LIKE '% Season%' THEN split_part(duration_ok, ' ', 1)::smallint END AS temporadas,
    description                                                   AS descripcion,
    -- "Arts, Entertainment, and Culture" es UN género que contiene comas
    replace(listed_in, 'Arts, Entertainment, and Culture', 'Arts| Entertainment| and Culture') AS generos,
    country                                                       AS paises
FROM corregidas;
END;
$$;

-- ---------------------------------------------------------------------
-- Proceso de carga incremental (no volátil: nunca borra ni pisa la historia)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE dwh.sp_cargar_dwh()
LANGUAGE plpgsql AS $$
DECLARE
    p        record;
    v_carga  int;
    v_stg    int;
    v_nuevas int;
    v_act    int;
BEGIN
    CALL dwh.sp_preparar_staging();

    FOR p IN SELECT plataforma_id FROM dwh.plataforma ORDER BY 1 LOOP
        SELECT count(*) INTO v_stg FROM tmp_staging WHERE plataforma_id = p.plataforma_id;

        INSERT INTO dwh.control_carga (plataforma_id, filas_staging, filas_nuevas, filas_actualizadas)
        VALUES (p.plataforma_id, v_stg, 0, 0)
        RETURNING carga_id INTO v_carga;

        -- Altas y actualizaciones (upsert por clave natural plataforma + show_id)
        WITH upsert AS (
            INSERT INTO dwh.titulo AS t (plataforma_id, show_id, titulo, tipo, clasificacion_original,
                director, anio_estreno, fecha_agregado, duracion_min, temporadas, descripcion,
                carga_id_alta, carga_id_ultima)
            SELECT plataforma_id, show_id, titulo, tipo, clasificacion_original, director,
                   anio_estreno, fecha_agregado, duracion_min, temporadas, descripcion, v_carga, v_carga
            FROM tmp_staging
            WHERE plataforma_id = p.plataforma_id
            ON CONFLICT (plataforma_id, show_id) DO UPDATE SET
                titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo,
                clasificacion_original = EXCLUDED.clasificacion_original,
                director = EXCLUDED.director, anio_estreno = EXCLUDED.anio_estreno,
                fecha_agregado = EXCLUDED.fecha_agregado, duracion_min = EXCLUDED.duracion_min,
                temporadas = EXCLUDED.temporadas, descripcion = EXCLUDED.descripcion,
                carga_id_ultima = v_carga, fecha_ultima_vista = now()
            RETURNING (xmax = 0) AS es_nueva
        )
        SELECT count(*) FILTER (WHERE es_nueva), count(*) FILTER (WHERE NOT es_nueva)
        INTO v_nuevas, v_act FROM upsert;

        -- Relaciones N a N (solo se agregan, nunca se borran)
        INSERT INTO dwh.titulo_genero (titulo_id, genero_original)
        SELECT DISTINCT t.titulo_id, replace(trim(g), '|', ',')
        FROM tmp_staging s
        JOIN dwh.titulo t ON t.plataforma_id = s.plataforma_id AND t.show_id = s.show_id
        CROSS JOIN unnest(string_to_array(s.generos, ',')) AS g
        WHERE s.plataforma_id = p.plataforma_id AND trim(g) <> ''
        ON CONFLICT DO NOTHING;

        INSERT INTO dwh.titulo_pais (titulo_id, pais)
        SELECT DISTINCT t.titulo_id, trim(c)
        FROM tmp_staging s
        JOIN dwh.titulo t ON t.plataforma_id = s.plataforma_id AND t.show_id = s.show_id
        CROSS JOIN unnest(string_to_array(s.paises, ',')) AS c
        WHERE s.plataforma_id = p.plataforma_id AND trim(c) <> ''
        ON CONFLICT DO NOTHING;

        UPDATE dwh.control_carga
        SET filas_nuevas = v_nuevas, filas_actualizadas = v_act
        WHERE carga_id = v_carga;
    END LOOP;
END;
$$;
