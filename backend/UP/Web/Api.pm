package UP::Web::Api;

# =====================================================================
# Capa HTTP.
#
# Es la unica capa que sabe que existe el protocolo: lee el request,
# despacha segun el metodo, y traduce el resultado (o el error de
# negocio) a un status code y un JSON.
#
# Todo lo que esta debajo -- servicios, repositorios -- funciona igual
# si manana esto se expone por linea de comandos o por una cola de
# mensajes. Por eso el mapa codigo -> status vive aca y no en
# UP::Error.
# =====================================================================

use strict;
use warnings;

use Encode qw(decode_utf8);
use JSON::PP ();

use UP::Error;

# ---------------------------------------------------------------------
# Codigos de negocio traducidos a HTTP.
#
#   400 el pedido esta mal formado o los datos no pasan validacion
#   404 el recurso pedido no existe
#   405 el metodo no aplica a este endpoint
#   409 conflicto con el estado actual: es el caso de los duplicados,
#       que es justamente lo que pide la consigna
# ---------------------------------------------------------------------
my %ESTADO_POR_CODIGO = (
    VALIDACION           => 400,
    CARRERA_INVALIDA     => 400,
    NO_ENCONTRADO        => 404,
    METODO_NO_PERMITIDO  => 405,
    EMAIL_DUPLICADO      => 409,
    ALUMNO_YA_INSCRIPTO  => 409,
);

my %TEXTO_ESTADO = (
    200 => 'OK',
    201 => 'Created',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    409 => 'Conflict',
    500 => 'Internal Server Error',
);

# Cuerpo maximo aceptado. Sin este limite, un pedido con un
# Content-Length enorme haria que el proceso intente reservar toda esa
# memoria antes de rechazarlo.
my $MAXIMO_CUERPO = 64 * 1024;

my $ESTADO_SALIDA = 200;

# ---------------------------------------------------------------------
# Fija el status de una respuesta exitosa. Se usa para devolver 201 en
# las altas; por defecto es 200.
# ---------------------------------------------------------------------
sub estado {
    my ( $class, $numero ) = @_;
    $ESTADO_SALIDA = $numero if defined $numero;
    return $ESTADO_SALIDA;
}

sub metodo {
    return uc( $ENV{REQUEST_METHOD} || 'GET' );
}

# ---------------------------------------------------------------------
# Un parametro del query string, ya decodificado a caracteres.
# ---------------------------------------------------------------------
sub parametro {
    my ( $class, $nombre ) = @_;

    my $query = defined $ENV{QUERY_STRING} ? $ENV{QUERY_STRING} : '';

    for my $par ( split /[&;]/, $query ) {
        my ( $clave, $valor ) = split /=/, $par, 2;
        next unless defined $clave;
        next unless _desescapar($clave) eq $nombre;
        return defined $valor ? _desescapar($valor) : '';
    }

    return undef;
}

sub _desescapar {
    my ($texto) = @_;

    $texto =~ tr/+/ /;
    $texto =~ s/%([0-9A-Fa-f]{2})/chr( hex($1) )/ge;

    # Lo anterior deja bytes; el resto del programa trabaja con
    # caracteres. Si la secuencia no es UTF-8 valido se reemplaza en
    # vez de morir: un query string roto no deberia tumbar el endpoint.
    return decode_utf8( $texto, 0 );
}

# ---------------------------------------------------------------------
# Cuerpo del pedido, parseado como JSON.
# ---------------------------------------------------------------------
sub cuerpo_json {
    my ($class) = @_;

    my $largo = $ENV{CONTENT_LENGTH} || 0;
    return {} unless $largo;

    UP::Error->lanzar( 'VALIDACION', 'El pedido es demasiado grande.' )
        if $largo > $MAXIMO_CUERPO;

    my $crudo = '';
    binmode STDIN;
    read STDIN, $crudo, $largo;

    # ->utf8 porque lo que se leyo son bytes, no caracteres.
    my $datos = eval { JSON::PP->new->utf8->decode($crudo) };

    UP::Error->lanzar( 'VALIDACION', 'El cuerpo del pedido no es JSON válido.' )
        if $@ || ref($datos) ne 'HASH';

    return $datos;
}

# =====================================================================
# Punto de entrada de cada .cgi.
#
#     UP::Web::Api->despachar({
#         GET  => sub { ... },
#         POST => sub { ... },
#     });
#
# El handler devuelve la estructura de datos a serializar. Cualquier
# error de negocio que lance sale como JSON con el status que
# corresponda; cualquier otra excepcion sale como 500 generico.
# =====================================================================
sub despachar {
    my ( $class, $manejadores ) = @_;

    my $resultado = eval {
        my $metodo = $class->metodo;

        my $manejador = $manejadores->{$metodo};

        UP::Error->lanzar( 'METODO_NO_PERMITIDO',
            "El método $metodo no está disponible en este recurso." )
            unless $manejador;

        $manejador->();
    };

    if ($@) {
        my $error = $@;
        return $class->_responder_error($error);
    }

    return $class->_responder( $ESTADO_SALIDA,
        { ok => JSON::PP::true, data => $resultado } );
}

# ---------------------------------------------------------------------
sub _responder_error {
    my ( $class, $error ) = @_;

    if ( UP::Error->es($error) ) {
        my $estado = $ESTADO_POR_CODIGO{ $error->codigo } || 400;
        return $class->_responder( $estado,
            { ok => JSON::PP::false, error => $error->a_hash } );
    }

    # Excepcion inesperada: un bug, o la base caida.
    #
    # El detalle va al error_log de Apache y NO al cliente: esos
    # mensajes suelen incluir fragmentos de SQL, rutas del servidor o
    # la cadena de conexion, que no tienen por que salir a la calle.
    my $detalle = "$error";
    $detalle =~ s/\s+$//;
    print STDERR "[UP] error inesperado: $detalle\n";

    return $class->_responder(
        500,
        {   ok    => JSON::PP::false,
            error => {
                codigo  => 'ERROR_INTERNO',
                mensaje => 'Ocurrió un error inesperado. Probá de nuevo en unos minutos.',
            },
        }
    );
}

# ---------------------------------------------------------------------
sub _responder {
    my ( $class, $estado, $cuerpo ) = @_;

    # ->utf8 devuelve bytes; ->canonical ordena las claves, lo que hace
    # que la salida sea estable y comparable entre corridas.
    my $json = JSON::PP->new->utf8->canonical->encode($cuerpo);

    my $texto = $TEXTO_ESTADO{$estado} || 'Status';

    binmode STDOUT;

    print "Status: $estado $texto\r\n";
    print "Content-Type: application/json; charset=utf-8\r\n";
    print "Content-Length: " . length($json) . "\r\n";

    # Que ningun intermediario cachee respuestas de datos.
    print "Cache-Control: no-store\r\n";

    # Sin esto, un navegador podria interpretar la respuesta como algo
    # distinto de JSON si el contenido lo confunde.
    print "X-Content-Type-Options: nosniff\r\n";

    print "\r\n";
    print $json;

    return;
}

1;
