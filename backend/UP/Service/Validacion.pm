package UP::Service::Validacion;

# =====================================================================
# Validacion y normalizacion de los datos que llegan de afuera.
#
# Esta es la validacion que manda. La del formulario HTML solo da
# respuesta rapida, y se saltea con curl o desactivando JavaScript.
#
# Los errores se juntan y se devuelven todos a la vez: si alguien
# manda tres campos mal, que los vea los tres de una.
# =====================================================================

use strict;
use warnings;
use utf8;

use UP::Error;

my $LARGO = {
    nombre       => 120,
    email        => 160,
    telefono     => 40,
    nacionalidad => 80,
};

# ---------------------------------------------------------------------
# Saca espacios de los extremos y colapsa los internos.
# Sin esto, "  Ana   Perez " y "Ana Perez" entrarian como distintos.
# ---------------------------------------------------------------------
sub _limpiar {
    my ($valor) = @_;
    return undef unless defined $valor;

    $valor =~ s/^\s+//;
    $valor =~ s/\s+$//;
    $valor =~ s/\s+/ /g;

    return length($valor) ? $valor : undef;
}

# ---------------------------------------------------------------------
# Valida los datos de un alumno.
#
#   $datos              hashref crudo, tal como llego del request
#   requiere_carrera    ademas exige y valida carrera_id
#
# Devuelve un hashref nuevo, ya normalizado. Nunca modifica el original.
# Lanza UP::Error 'VALIDACION' con el detalle por campo si algo falla.
# ---------------------------------------------------------------------
sub validar_alumno {
    my ( $datos, %opciones ) = @_;

    $datos ||= {};
    my %error;
    my %limpio;

    # --- nombre ------------------------------------------------------
    $limpio{nombre} = _limpiar( $datos->{nombre} );
    if ( !defined $limpio{nombre} ) {
        $error{nombre} = 'El nombre es obligatorio.';
    }
    elsif ( length( $limpio{nombre} ) < 2 ) {
        $error{nombre} = 'El nombre es demasiado corto.';
    }
    elsif ( length( $limpio{nombre} ) > $LARGO->{nombre} ) {
        $error{nombre} = "El nombre no puede superar los $LARGO->{nombre} caracteres.";
    }

    # --- email -------------------------------------------------------
    # Alcanza para descartar lo groseramente invalido. Validar un email
    # "del todo" con una expresion regular es un pozo sin fondo, y
    # termina rechazando direcciones legitimas.
    $limpio{email} = _limpiar( $datos->{email} );
    if ( !defined $limpio{email} ) {
        $error{email} = 'El email es obligatorio.';
    }
    elsif ( length( $limpio{email} ) > $LARGO->{email} ) {
        $error{email} = "El email no puede superar los $LARGO->{email} caracteres.";
    }
    elsif ( $limpio{email} !~ /^[^@\s]+@[^@\s]+\.[^@\s]+$/ ) {
        $error{email} = 'El email no tiene un formato válido.';
    }

    # --- telefono (opcional) -----------------------------------------
    $limpio{telefono} = _limpiar( $datos->{telefono} );
    if ( defined $limpio{telefono} ) {
        if ( length( $limpio{telefono} ) > $LARGO->{telefono} ) {
            $error{telefono} = "El teléfono no puede superar los $LARGO->{telefono} caracteres.";
        }
        elsif ( $limpio{telefono} !~ /^[0-9+()\-\s]+$/ ) {
            $error{telefono} = 'El teléfono solo puede tener números, espacios y los signos + - ( ).';
        }
        elsif ( ( $limpio{telefono} =~ tr/0-9// ) < 6 ) {
            $error{telefono} = 'El teléfono es demasiado corto.';
        }
    }

    # --- nacionalidad (opcional) -------------------------------------
    $limpio{nacionalidad} = _limpiar( $datos->{nacionalidad} );
    if ( defined $limpio{nacionalidad}
        && length( $limpio{nacionalidad} ) > $LARGO->{nacionalidad} )
    {
        $error{nacionalidad} = "La nacionalidad no puede superar los $LARGO->{nacionalidad} caracteres.";
    }

    # --- carrera -----------------------------------------------------
    if ( $opciones{requiere_carrera} ) {
        my $id = validar_id( $datos->{carrera_id} );
        if ( defined $id ) {
            $limpio{carrera_id} = $id;
        }
        else {
            $error{carrera_id} = 'Elegí una carrera.';
        }
    }

    UP::Error->lanzar( 'VALIDACION', 'Hay datos que revisar.', campos => \%error )
        if %error;

    return \%limpio;
}

# ---------------------------------------------------------------------
# Un id valido es un entero positivo. Devuelve el numero o undef.
#
# Se valida aparte de los datos del alumno porque los ids llegan por
# la URL, no por el cuerpo del request.
# ---------------------------------------------------------------------
sub validar_id {
    my ($valor) = @_;

    return undef unless defined $valor;

    $valor =~ s/^\s+|\s+$//g;
    return undef unless $valor =~ /^[1-9][0-9]*$/;

    # Limite de un integer de PostgreSQL. Sin esto, un id enorme
    # llegaria a la base y volveria como error de rango en vez de como
    # "no encontrado", que es lo que corresponde.
    return undef if $valor > 2147483647;

    return $valor + 0;
}

1;
