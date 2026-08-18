package UP::Repo::Alumno;

# =====================================================================
# Acceso a datos de la tabla "alumno".
#
# Solo SQL, siempre con placeholders. Ningun valor se interpola en la
# sentencia: eso es lo que hace imposible la inyeccion SQL.
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
# Las carreras se agregan en la misma consulta con json_agg en lugar de
# hacer una consulta por alumno: con N alumnos eso serian N+1 viajes a
# la base.
#
# El FILTER es necesario por el LEFT JOIN: sin el, un alumno sin
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

    # El JSON se decodifica aca para que las capas de arriba reciban
    # estructuras Perl y nunca sepan que la base uso json_agg.
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
# El lower() del WHERE coincide con el del indice unico ux_alumno_email,
# asi que esta busqueda lo usa en vez de recorrer la tabla.
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
# Igual que buscar_por_email pero excluyendo un id.
#
# Sirve para la modificacion del ABM: al editar a alguien, su propio
# email no puede contar como duplicado.
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
# Modificacion. Devuelve la cantidad de filas afectadas: 0 significa
# que el id no existia.
#
# El "0 +" no es decorativo. Cuando no se afecta ninguna fila, DBI no
# devuelve 0 sino la cadena "0E0", que vale cero en contexto numerico
# pero es VERDADERA en contexto booleano. Sin normalizarla, un
# "unless $filas" nunca se cumpliria y una baja de algo inexistente
# pasaria por exitosa.
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
