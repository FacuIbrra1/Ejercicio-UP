package UP::Repo::Inscripcion;

# =====================================================================
# Acceso a datos de la tabla "inscripcion", la relacion N:M entre
# alumno y carrera.
#
# Solo SQL.
# =====================================================================

use strict;
use warnings;

# ---------------------------------------------------------------------
# Inscripciones de un alumno, con el nombre de la carrera resuelto.
# ---------------------------------------------------------------------
sub listar_por_alumno {
    my ( $dbh, $alumno_id ) = @_;

    return $dbh->selectall_arrayref(
        q{
            SELECT i.id            AS inscripcion_id,
                   c.id            AS carrera_id,
                   c.nombre        AS carrera_nombre,
                   to_char(i.creada_en AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS creada_en
              FROM inscripcion i
              JOIN carrera     c ON c.id = i.carrera_id
             WHERE i.alumno_id = ?
             ORDER BY c.nombre
        },
        { Slice => {} },
        $alumno_id
    );
}

# ---------------------------------------------------------------------
# Una inscripcion por id, o undef.
# ---------------------------------------------------------------------
sub buscar_por_id {
    my ( $dbh, $id ) = @_;

    return $dbh->selectrow_hashref(
        'SELECT id, alumno_id, carrera_id FROM inscripcion WHERE id = ?',
        undef,
        $id
    );
}

# ---------------------------------------------------------------------
# Ya existe este alumno en esta carrera?
#
# Es la consulta que permite devolver ALUMNO_YA_INSCRIPTO con un mensaje
# claro. La garantia real contra duplicados no es esta consulta sino la
# constraint ux_inscripcion_alumno_carrera: entre este SELECT y el
# INSERT posterior puede colarse otro proceso.
# ---------------------------------------------------------------------
sub existe {
    my ( $dbh, $alumno_id, $carrera_id ) = @_;

    my ($existe) = $dbh->selectrow_array(
        'SELECT 1 FROM inscripcion WHERE alumno_id = ? AND carrera_id = ?',
        undef,
        $alumno_id, $carrera_id
    );

    return $existe ? 1 : 0;
}

# ---------------------------------------------------------------------
# Alta. Devuelve el id generado.
# ---------------------------------------------------------------------
sub insertar {
    my ( $dbh, $alumno_id, $carrera_id ) = @_;

    my ($id) = $dbh->selectrow_array(
        'INSERT INTO inscripcion (alumno_id, carrera_id)
              VALUES (?, ?)
           RETURNING id',
        undef,
        $alumno_id, $carrera_id
    );

    return $id;
}

# ---------------------------------------------------------------------
# Baja. Devuelve filas afectadas: 0 significa que el id no existia.
#
# El "0 +" normaliza el "0E0" que devuelve DBI cuando no afecta filas:
# esa cadena vale cero en contexto numerico pero es VERDADERA como
# booleano, asi que sin esto un borrado de algo inexistente pasaria
# por exitoso.
# ---------------------------------------------------------------------
sub borrar {
    my ( $dbh, $id ) = @_;

    return 0 + $dbh->do( 'DELETE FROM inscripcion WHERE id = ?', undef, $id );
}

# ---------------------------------------------------------------------
# Cuantos alumnos hay en una carrera. Lo usa el ABM para avisar antes
# de intentar borrar una carrera protegida por el ON DELETE RESTRICT.
# ---------------------------------------------------------------------
sub contar_por_carrera {
    my ( $dbh, $carrera_id ) = @_;

    my ($total) = $dbh->selectrow_array(
        'SELECT count(*) FROM inscripcion WHERE carrera_id = ?',
        undef,
        $carrera_id
    );

    return $total;
}

1;
