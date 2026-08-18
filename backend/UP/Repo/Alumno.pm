package UP::Repo::Alumno;

# =====================================================================
# Acceso a datos de la tabla "alumno".
#
# Solo SQL, siempre con placeholders. Ningun valor se pega dentro de
# la sentencia, y por eso la inyeccion SQL no es posible.
# =====================================================================

use strict;
use warnings;

use JSON::PP ();

# creado_en se devuelve como ISO 8601 en UTC para que el formato no
# dependa del locale del servidor.
my $COLUMNAS = q{
    id, nombre, email, telefono, nacionalidad,
    to_char(creado_en AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS creado_en
};

my $JSON = JSON::PP->new;

# ---------------------------------------------------------------------
# Listado completo, cada alumno con sus carreras.
#
# json_agg trae las carreras en la misma consulta. La alternativa
# serian N+1 viajes a la base: uno por los alumnos y uno por cada uno.
#
# El FILTER hace falta por el LEFT JOIN: sin el, un alumno sin
# inscripciones daria [null] en vez de [].
# ---------------------------------------------------------------------
sub listar {
    my ($dbh) = @_;

    my $sql = qq{
        SELECT a.id,
               a.nombre,
               a.email,
               a.telefono,
               a.nacionalidad,
               to_char(a.creado_en AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS creado_en,
               COALESCE(
                   json_agg(
                       json_build_object(
                           'inscripcion_id', i.id,
                           'carrera_id',     c.id,
                           'carrera_nombre', c.nombre
                       )
                       ORDER BY c.nombre
                   ) FILTER (WHERE i.id IS NOT NULL),
                   '[]'::json
               ) AS carreras
          FROM alumno a
          LEFT JOIN inscripcion i ON i.alumno_id = a.id
          LEFT JOIN carrera     c ON c.id = i.carrera_id
         GROUP BY a.id
         ORDER BY a.nombre
    };

    my $filas = $dbh->selectall_arrayref( $sql, { Slice => {} } );

    # Se decodifica aca para que las capas de arriba reciban
    # estructuras Perl y no se enteren de que la base uso json_agg.
    $_->{carreras} = $JSON->decode( $_->{carreras} ) for @$filas;

    return $filas;
}

# ---------------------------------------------------------------------
# Un alumno por id, o undef.
# ---------------------------------------------------------------------
sub buscar_por_id {
    my ( $dbh, $id ) = @_;

    return $dbh->selectrow_hashref(
        "SELECT $COLUMNAS FROM alumno WHERE id = ?",
        undef,
        $id
    );
}

# ---------------------------------------------------------------------
# Un alumno por email, sin distinguir mayusculas.
#
# El lower() es el mismo que usa el indice ux_alumno_email, asi que la
# busqueda lo aprovecha en vez de recorrer la tabla entera.
# ---------------------------------------------------------------------
sub buscar_por_email {
    my ( $dbh, $email ) = @_;

    return $dbh->selectrow_hashref(
        "SELECT $COLUMNAS FROM alumno WHERE lower(email) = lower(?)",
        undef,
        $email
    );
}

# ---------------------------------------------------------------------
# Igual que buscar_por_email pero salteando un id.
#
# La usa la edicion del ABM: el email propio del alumno no puede
# contar como duplicado.
# ---------------------------------------------------------------------
sub buscar_por_email_excepto {
    my ( $dbh, $email, $id_excluido ) = @_;

    return $dbh->selectrow_hashref(
        "SELECT $COLUMNAS FROM alumno WHERE lower(email) = lower(?) AND id <> ?",
        undef,
        $email, $id_excluido
    );
}

# ---------------------------------------------------------------------
# Alta. Devuelve el id generado.
# ---------------------------------------------------------------------
sub insertar {
    my ( $dbh, $datos ) = @_;

    my ($id) = $dbh->selectrow_array(
        'INSERT INTO alumno (nombre, email, telefono, nacionalidad)
              VALUES (?, ?, ?, ?)
           RETURNING id',
        undef,
        @{$datos}{qw(nombre email telefono nacionalidad)}
    );

    return $id;
}

# ---------------------------------------------------------------------
# Modificacion. Devuelve cuantas filas cambio: 0 significa que el id
# no existia.
#
# Ojo con el "0 +". Cuando no toca ninguna fila, DBI devuelve la
# cadena "0E0", que vale cero pero es verdadera como booleano. Sin
# convertirla, un "unless $filas" nunca se cumple.
# ---------------------------------------------------------------------
sub actualizar {
    my ( $dbh, $id, $datos ) = @_;

    return 0 + $dbh->do(
        'UPDATE alumno
            SET nombre       = ?,
                email        = ?,
                telefono     = ?,
                nacionalidad = ?
          WHERE id = ?',
        undef,
        @{$datos}{qw(nombre email telefono nacionalidad)},
        $id
    );
}

# ---------------------------------------------------------------------
# Baja. Las inscripciones del alumno se van solas por el ON DELETE
# CASCADE de la clave foranea.
#
# Ver el comentario sobre "0E0" en actualizar().
# ---------------------------------------------------------------------
sub borrar {
    my ( $dbh, $id ) = @_;

    return 0 + $dbh->do( 'DELETE FROM alumno WHERE id = ?', undef, $id );
}

1;
