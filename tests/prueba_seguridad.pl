#!/usr/bin/env perl

# =====================================================================
# Prueba de control de acceso.
#
#     perl tests/prueba_seguridad.pl [url_base] [usuario:clave]
#
# Verifica que la parte publica siga abierta, que la privada este
# cerrada -- HTML *y* endpoints -- y que los archivos internos no
# tengan URL.
#
# El chequeo que mas importa es que admin/api/ pida credenciales. Si
# solo estuviera protegido el HTML, cualquiera podria pegarle directo
# a la API y borrar alumnos sin ver nunca la pantalla de login.
# =====================================================================

use strict;
use warnings;
use utf8;

use HTTP::Tiny;
use MIME::Base64 qw(encode_base64);

binmode STDOUT, ':encoding(UTF-8)';

my $BASE  = shift(@ARGV) || 'http://localhost/up';
my $LOGIN = shift(@ARGV) || 'admin:up2026';

$BASE =~ s{/+$}{};

my $http = HTTP::Tiny->new( timeout => 20 );

my $fallos = 0;
my $paso   = 0;

sub check {
    my ( $condicion, $descripcion, $detalle ) = @_;
    $paso++;
    printf "%2d. %-52s %s%s\n", $paso, $descripcion,
        ( $condicion ? 'OK' : 'FALLO' ),
        ( defined $detalle ? "  ($detalle)" : '' );
    $fallos++ unless $condicion;
    return;
}

sub pedir {
    my ( $metodo, $ruta, $credencial ) = @_;

    my %opciones;
    if ($credencial) {
        $opciones{headers}{'Authorization'}
            = 'Basic ' . encode_base64( $credencial, '' );
    }

    return $http->request( $metodo, "$BASE$ruta", \%opciones );
}

print "Base: $BASE\n\n";

print "--- La parte pública sigue abierta ---\n";

for my $ruta ( '/', '/api/carreras.cgi', '/css/estilos.css', '/js/inscripcion.js' ) {
    my $r = pedir( 'GET', $ruta );
    check( $r->{status} == 200, "GET $ruta sin credenciales", "HTTP $r->{status}" );
}

print "\n--- La parte privada está cerrada ---\n";

# Todos los metodos, no solo GET: proteger la lectura y dejar abierto
# el DELETE seria peor que no proteger nada.
my @privadas = (
    [ 'GET',    '/admin/' ],
    [ 'GET',    '/admin/index.html' ],
    [ 'GET',    '/admin/api/alumnos.cgi' ],
    [ 'GET',    '/admin/api/carreras.cgi' ],
    [ 'POST',   '/admin/api/alumnos.cgi' ],
    [ 'PUT',    '/admin/api/alumnos.cgi?id=1' ],
    [ 'DELETE', '/admin/api/alumnos.cgi?id=1' ],
    [ 'POST',   '/admin/api/inscripciones.cgi' ],
    [ 'DELETE', '/admin/api/inscripciones.cgi?id=1' ],
);

for my $caso (@privadas) {
    my ( $metodo, $ruta ) = @$caso;
    my $r = pedir( $metodo, $ruta );
    check( $r->{status} == 401, "$metodo $ruta sin credenciales", "HTTP $r->{status}" );
}

{
    my $r = pedir( 'GET', '/admin/api/alumnos.cgi', 'admin:clave-incorrecta' );
    check( $r->{status} == 401, 'Credenciales incorrectas', "HTTP $r->{status}" );

    my $r2 = pedir( 'GET', '/admin/api/alumnos.cgi', 'usuario-inventado:up2026' );
    check( $r2->{status} == 401, 'Usuario inexistente', "HTTP $r2->{status}" );
}

{
    my $r = pedir( 'GET', '/admin/', $LOGIN );
    check( $r->{status} == 200, 'Con credenciales correctas entra', "HTTP $r->{status}" );

    my $r2 = pedir( 'GET', '/admin/api/alumnos.cgi', $LOGIN );
    check( $r2->{status} == 200, 'Y la API privada responde', "HTTP $r2->{status}" );
}

{
    my $r = pedir( 'GET', '/admin/' );
    my $desafio = $r->{headers}{'www-authenticate'} || '';
    check( $desafio =~ /Basic/i, 'El 401 manda el desafío WWW-Authenticate', $desafio );
}

print "\n--- Archivos internos sin URL ---\n";

# .htpasswd es el mas importante: si se pudiera descargar, los hashes
# quedarian expuestos a un ataque de fuerza bruta offline.
my @internos = (
    '/config/.htpasswd',
    '/config/app.conf',
    '/admin/.htaccess',
    '/backend/UP/DB.pm',
    '/backend/UP/Config.pm',
    '/backend/UP/Service/Validacion.pm',
    '/database/00_crear_base.sql',
    '/tests/prueba_api.pl',
    '/docs/PLAN.md',

    # Los alias apuntan a frontend/publico y frontend/admin, asi que
    # estas rutas intentan salirse de ahi hacia el resto del proyecto.
    '/../config/.htpasswd',
    '/../backend/UP/DB.pm',
    '/admin/../../config/app.conf',
    '/frontend/publico/index.html',    # el arbol interno tampoco se expone
);

for my $ruta (@internos) {
    my $r = pedir( 'GET', $ruta, $LOGIN );
    my $contenido = $r->{content} // '';

    # No alcanza con mirar el status: lo que importa es que el
    # contenido sensible no haya salido.
    my $filtrado = $contenido =~ /\$2y\$|db_pass|AuthUserFile|CREATE ROLE|package UP::/;

    check( $r->{status} >= 400 && !$filtrado,
        "No se puede leer $ruta", "HTTP $r->{status}" );
}

print "\n--- Cabeceras de seguridad ---\n";

{
    my $r = pedir( 'GET', '/' );

    my %esperadas = (
        'x-content-type-options'  => qr/nosniff/i,
        'x-frame-options'         => qr/DENY/i,
        'referrer-policy'         => qr/same-origin/i,
        'content-security-policy' => qr/default-src 'self'/,
    );

    for my $cabecera ( sort keys %esperadas ) {
        my $valor = $r->{headers}{$cabecera} // '';
        check( $valor =~ $esperadas{$cabecera}, "Cabecera $cabecera", $valor || 'ausente' );
    }
}

print "\n";
if ($fallos) {
    print "RESULTADO: $fallos de $paso chequeos fallaron.\n";
    exit 1;
}
print "RESULTADO: los $paso chequeos pasaron.\n";
exit 0;
