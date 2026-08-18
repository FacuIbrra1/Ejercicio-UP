-- =====================================================================
-- 00_crear_base.sql  ·  Rol de aplicacion y base de datos
-- ---------------------------------------------------------------------
-- Ejecutar UNA VEZ como superusuario, conectado a la base "postgres":
--
--     psql -U postgres -f database/00_crear_base.sql
--
-- Va a pedir la contrasena del usuario "postgres" que definiste al
-- instalar PostgreSQL.
--
-- Es idempotente: se puede correr de nuevo sin romper nada.
-- =====================================================================

\set ON_ERROR_STOP on
SET client_encoding TO 'UTF8';

-- ---------------------------------------------------------------------
-- Rol de la aplicacion.
-- La app nunca se conecta como superusuario: solo necesita leer y
-- escribir sus propias tablas.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'up_app') THEN
        CREATE ROLE up_app LOGIN PASSWORD 'up_app_dev';
        RAISE NOTICE 'Rol "up_app" creado.';
    ELSE
        RAISE NOTICE 'El rol "up_app" ya existia, no se modifico.';
    END IF;
END
$$;

-- ---------------------------------------------------------------------
-- Base de datos, con up_app como duena (asi puede crear sus tablas).
--
-- CREATE DATABASE no puede ir dentro de un bloque DO, porque no corre
-- dentro de una transaccion. Por eso se arma la sentencia con un
-- SELECT condicional y se ejecuta con \gexec.
-- ---------------------------------------------------------------------
SELECT 'CREATE DATABASE inscripciones_up OWNER up_app'
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = 'inscripciones_up'
)
\gexec

\echo ''
\echo '--- Estado ---'
SELECT d.datname                             AS base,
       pg_catalog.pg_get_userbyid(d.datdba)  AS duenio,
       pg_encoding_to_char(d.encoding)       AS encoding
  FROM pg_database d
 WHERE d.datname = 'inscripciones_up';

\echo ''
\echo 'Listo. Siguiente paso:'
\echo '  psql -U up_app -d inscripciones_up -f database/01_schema.sql'
