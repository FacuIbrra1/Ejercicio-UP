package UP::Error;

# =====================================================================
# Error de negocio tipado.
#
# La capa de servicios lanza estos errores con die; la capa web los
# atrapa con eval y los convierte en una respuesta JSON.
#
# A proposito NO sabe nada de HTTP: no tiene status code ni nada
# parecido. La traduccion codigo -> HTTP vive en UP::Web::Api, que es
# la unica capa que deberia saber que existe el protocolo. Asi este
# mismo error sirve igual si manana esto se expone por linea de
# comandos o por una cola de mensajes.
#
# Codigos posibles:
#   VALIDACION           datos mal formados (trae el detalle por campo)
#   EMAIL_DUPLICADO      ya existe otro alumno con ese email
#   ALUMNO_YA_INSCRIPTO  ese alumno ya esta en esa carrera
#   CARRERA_INVALIDA     la carrera no existe o no esta activa
#   NO_ENCONTRADO        el id pedido no existe
# =====================================================================

use strict;
use warnings;

use Scalar::Util qw(blessed);

use overload
    '""'     => sub { $_[0]->{mensaje} },
    fallback => 1;

# ---------------------------------------------------------------------
#   UP::Error->lanzar('EMAIL_DUPLICADO', 'Ya existe...');
#   UP::Error->lanzar('VALIDACION', 'Revisa los datos', campos => {...});
# ---------------------------------------------------------------------
sub lanzar {
    my ( $class, $codigo, $mensaje, %extra ) = @_;

    die bless {
        codigo  => $codigo,
        mensaje => $mensaje,
        campos  => $extra{campos} || {},
    }, $class;
}

sub codigo  { return $_[0]->{codigo} }
sub mensaje { return $_[0]->{mensaje} }
sub campos  { return $_[0]->{campos} }

# ---------------------------------------------------------------------
# Es esto un error de negocio, o una excepcion cualquiera de Perl?
#
# Importa distinguirlos: un UP::Error se le muestra al usuario tal
# cual, mientras que cualquier otra excepcion es un bug o una falla de
# infraestructura, y de esa solo se muestra un mensaje generico.
#
# Usa blessed() y no un eval defensivo alrededor de isa() porque un
# eval, aun exitoso, limpia $@. Eso romperia el uso natural de esta
# funcion:
#
#     if (UP::Error->es($@)) { $@->codigo }   # $@ ya estaria vacio
#
# Con blessed() no hay eval de por medio y $@ queda intacto.
# ---------------------------------------------------------------------
sub es {
    my ( $class, $cosa ) = @_;
    return blessed($cosa) && $cosa->isa(__PACKAGE__) ? 1 : 0;
}

# ---------------------------------------------------------------------
# Traduce un error de la base a un error de negocio segun su SQLSTATE.
#
#   UP::Error->desde_sqlstate( $dbh->state, $@, {
#       '23505' => [ 'EMAIL_DUPLICADO', 'Ya existe...' ],
#   });
#
# Lo que no este en el mapa se vuelve a lanzar tal cual: es un bug o
# una falla de infraestructura, y disfrazarlo de error de negocio solo
# lo esconderia.
#
# Recibe el SQLSTATE ya extraido y no el handle de la base, para no
# meter DBI dentro de esta clase.
# ---------------------------------------------------------------------
sub desde_sqlstate {
    my ( $class, $estado, $error_original, $mapa ) = @_;

    $estado = '' unless defined $estado;

    if ( my $traduccion = $mapa->{$estado} ) {
        $class->lanzar(@$traduccion);
    }

    die $error_original;
}

# ---------------------------------------------------------------------
# Estructura lista para serializar a JSON.
# ---------------------------------------------------------------------
sub a_hash {
    my ($self) = @_;

    my %h = (
        codigo  => $self->{codigo},
        mensaje => $self->{mensaje},
    );
    $h{campos} = $self->{campos} if %{ $self->{campos} };

    return \%h;
}

1;
