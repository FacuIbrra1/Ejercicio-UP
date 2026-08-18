package UP::Repo::Carrera;

# =====================================================================
# Acceso a datos de la tabla "carrera".
#
# Solo SQL. Las validaciones y las reglas viven en UP::Service::*.
#
# Todas las funciones reciben el handle como primer argumento en vez
# de pedirselo a UP::DB, asi el service puede pasarles el mismo handle
# dentro de una transaccion.
# =====================================================================

use strict;
use warnings;

my $COLUMNAS = 'id, nombre, activa';

# ---------------------------------------------------------------------
# Listado de carreras.
#   solo_activas => 1   limita a las ofrecidas en el formulario publico
# ---------------------------------------------------------------------
sub listar {
    my ( $dbh, %opciones ) = @_;

    my $sql = "SELECT $COLUMNAS FROM carrera";
    $sql .= ' WHERE activa = TRUE' if $opciones{solo_activas};
    $sql .= ' ORDER BY nombre';

    return $dbh->selectall_arrayref( $sql, { Slice => {} } );
}

# ---------------------------------------------------------------------
# Una carrera por id, o undef si no existe.
# ---------------------------------------------------------------------
sub buscar_por_id {
    my ( $dbh, $id ) = @_;

    return $dbh->selectrow_hashref(
        "SELECT $COLUMNAS FROM carrera WHERE id = ?",
        undef,
        $id
    );
}

# ---------------------------------------------------------------------
# Existe y esta activa. Se usa para validar el carrera_id que llega
# desde el formulario sin traerse la fila entera.
# ---------------------------------------------------------------------
sub existe_activa {
    my ( $dbh, $id ) = @_;

    my ($existe) = $dbh->selectrow_array(
        'SELECT 1 FROM carrera WHERE id = ? AND activa = TRUE',
        undef,
        $id
    );

    return $existe ? 1 : 0;
}

1;
