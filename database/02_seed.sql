-- =====================================================================
-- 02_seed.sql  ·  Datos iniciales
-- ---------------------------------------------------------------------
--     psql -U up_app -d inscripciones_up -f database/02_seed.sql
--
-- Solo carga carreras. Los alumnos se dan de alta desde la aplicacion.
-- Es idempotente: re-ejecutarlo no duplica ni pisa nada.
-- =====================================================================

\set ON_ERROR_STOP on
SET client_encoding TO 'UTF8';

INSERT INTO carrera (nombre) VALUES
    ('Arquitectura'),
    ('Diseño Gráfico'),
    ('Diseño de Indumentaria y Textil'),
    ('Publicidad'),
    ('Relaciones Públicas'),
    ('Psicología'),
    ('Abogacía'),
    ('Contador Público'),
    ('Licenciatura en Administración'),
    ('Ingeniería Informática'),
    ('Licenciatura en Comunicación Audiovisual'),
    ('Licenciatura en Hotelería')
ON CONFLICT (nombre) DO NOTHING;

\echo ''
\echo '--- Carreras cargadas ---'
SELECT id, nombre, activa FROM carrera ORDER BY nombre;
