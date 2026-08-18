-- =====================================================================
-- 01_schema.sql  ·  Estructura de la base
-- ---------------------------------------------------------------------
-- Ejecutar como up_app sobre la base ya creada por 00_crear_base.sql:
--
--     psql -U up_app -d inscripciones_up -f database/01_schema.sql
--
-- ATENCION: este script es re-ejecutable, y para lograrlo BORRA las
-- tablas existentes. Correrlo sobre una base con datos los elimina.
-- =====================================================================

\set ON_ERROR_STOP on
SET client_encoding TO 'UTF8';

-- ---------------------------------------------------------------------
-- La app guarda nombres con tildes y enies. Si la base no es UTF8 se
-- corrompen, y conviene enterarse ahora y no cuando falle una insercion.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    enc text;
BEGIN
    SELECT pg_encoding_to_char(encoding) INTO enc
      FROM pg_database
     WHERE datname = current_database();

    IF enc <> 'UTF8' THEN
        RAISE EXCEPTION
            'La base "%" tiene encoding % y se necesita UTF8. Recrearla con: CREATE DATABASE inscripciones_up OWNER up_app ENCODING ''UTF8'' TEMPLATE template0;',
            current_database(), enc;
    END IF;
END
$$;

-- ---------------------------------------------------------------------
-- Se borra en orden inverso a las dependencias: primero la tabla que
-- tiene las claves foraneas, despues las referenciadas.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS inscripcion;
DROP TABLE IF EXISTS alumno;
DROP TABLE IF EXISTS carrera;


-- =====================================================================
-- carrera
-- =====================================================================
CREATE TABLE carrera (
    id     SERIAL       PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    activa BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT ux_carrera_nombre UNIQUE (nombre),
    CONSTRAINT ck_carrera_nombre CHECK (btrim(nombre) <> '')
);

COMMENT ON TABLE  carrera        IS 'Carreras disponibles para inscripcion.';
COMMENT ON COLUMN carrera.activa IS 'Solo las activas se ofrecen en el formulario publico.';


-- =====================================================================
-- alumno
--
-- El email identifica al alumno de forma unica en todo el sistema.
-- La carrera NO vive aca: un alumno puede estar inscripto a varias,
-- y esa relacion la maneja la tabla "inscripcion".
-- =====================================================================
CREATE TABLE alumno (
    id           SERIAL       PRIMARY KEY,
    nombre       VARCHAR(120) NOT NULL,
    email        VARCHAR(160) NOT NULL,
    telefono     VARCHAR(40),
    nacionalidad VARCHAR(80),
    creado_en    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT ck_alumno_nombre CHECK (btrim(nombre) <> ''),
    -- Validacion deliberadamente laxa: descarta lo groseramente invalido
    -- sin pelearse con los casos raros pero legitimos.
    CONSTRAINT ck_alumno_email  CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$')
);

-- Sobre lower(email): "Juan@UP.edu.ar" y "juan@up.edu.ar" son la misma
-- persona. Este indice es el que dispara el error EMAIL_DUPLICADO.
CREATE UNIQUE INDEX ux_alumno_email ON alumno (lower(email));

COMMENT ON TABLE alumno IS 'Personas registradas. Una fila por persona, sin importar a cuantas carreras se anote.';


-- =====================================================================
-- inscripcion
--
-- Relacion N:M entre alumno y carrera. Cada fila es una inscripcion
-- concreta: un alumno en una carrera.
-- =====================================================================
CREATE TABLE inscripcion (
    id         SERIAL      PRIMARY KEY,
    alumno_id  INTEGER     NOT NULL,
    carrera_id INTEGER     NOT NULL,
    creada_en  TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Al dar de baja un alumno desde el ABM se van sus inscripciones.
    CONSTRAINT fk_inscripcion_alumno
        FOREIGN KEY (alumno_id) REFERENCES alumno (id) ON DELETE CASCADE,

    -- Una carrera con gente anotada no se puede borrar.
    CONSTRAINT fk_inscripcion_carrera
        FOREIGN KEY (carrera_id) REFERENCES carrera (id) ON DELETE RESTRICT,

    -- Esta es la regla central del ejercicio: el mismo alumno no puede
    -- inscribirse dos veces a la misma carrera. Dispara ALUMNO_YA_INSCRIPTO.
    CONSTRAINT ux_inscripcion_alumno_carrera UNIQUE (alumno_id, carrera_id)
);

-- Acelera el listado del ABM, que agrupa inscripciones por alumno.
CREATE INDEX ix_inscripcion_alumno  ON inscripcion (alumno_id);
CREATE INDEX ix_inscripcion_carrera ON inscripcion (carrera_id);

COMMENT ON TABLE inscripcion IS 'Un alumno inscripto en una carrera. El par (alumno, carrera) es unico.';


\echo ''
\echo '--- Tablas creadas ---'
SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;

\echo ''
\echo 'Listo. Siguiente paso:'
\echo '  psql -U up_app -d inscripciones_up -f database/02_seed.sql'
