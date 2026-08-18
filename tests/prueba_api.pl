#!/usr/bin/env perl

# =====================================================================
# Prueba de la API por HTTP, contra Apache corriendo.
#
#     perl tests/prueba_api.pl [url_base] [usuario:clave]
#
# Por defecto apunta a http://localhost/up
#
# A diferencia de las pruebas anteriores, esta no importa ningun modulo
# del proyecto: habla con la aplicacion por la red, igual que lo hara
# el navegador. Si algo esta mal configurado en Apache, se nota aca.
#
# Usa HTTP::Tiny, que viene con Perl: no agrega dependencias.
# =====================================================================

use strict;
use warnings;
use utf8;

use HTTP::Tiny;
use JSON::PP ();
use MIME::Base64 qw(encode_base64);

binmode STDOUT, ':encoding(UTF-8)';

my $BASE  = shift(@ARGV) || 'http://localhost/up';
my $LOGIN = shift(@ARGV) || '';    # usuario:clave para la parte privada

$BASE =~ s{/+$}{};

my $http = HTTP::Tiny->new( timeout => 20 );
my $json = JSON::PP->new->utf8->canonical;

my $fallos = 0;
my $paso   = 0;

sub check {
    my ( $condicion, $descripcion, $detalle ) = @_;
    $paso++;
    printf "%2d. %-50s %s%s\n", $paso, $descripcion,
        ( $condicion ? 'OK' : 'FALLO' ),
        ( defined $detalle ? "  ($detalle)" : '' );
    $fallos++ unless $condicion;
    return;
}

# ---------------------------------------------------------------------
# Devuelve (status, cuerpo_decodificado).
# La parte privada lleva Basic Auth si se paso usuario:clave.
# ---------------------------------------------------------------------
sub pedir {
    my ( $metodo, $ruta, $datos ) = @_;

    my %opciones;

    if ( defined $datos ) {
        $opciones{content} = ref($datos) ? $json->encode($datos) : $datos;
        $opciones{headers}{'Content-Type'} = 'application/json';
    }

    if ( $LOGIN && $ruta =~ m{^/admin} ) {
        my $credencial = encode_base64( $LOGIN, '' );
        $opciones{headers}{'Authorization'} = "Basic $credencial";
    }

    my $respuesta = $http->request( $metodo, "$BASE$ruta", \%opciones );

    my $cuerpo = eval { $json->decode( $respuesta->{content} ) };

    return ( $respuesta->{status}, $cuerpo, $respuesta->{content} );
}

sub codigo_error {
    my ($cuerpo) = @_;
    return '' unless ref($cuerpo) eq 'HASH' && ref( $cuerpo->{error} ) eq 'HASH';
    return $cuerpo->{error}{codigo} // '';
}

my $sufijo = time();
my $EMAIL  = "api.$sufijo\@up.edu.ar";
my $EMAIL2 = "api.dos.$sufijo\@up.edu.ar";

print "Base: $BASE\n";
print "Auth: " . ( $LOGIN ? 'si' : 'no (la parte privada todavia no esta protegida)' ) . "\n\n";

print "--- Parte publica ---\n";

my ( $carrera_a, $carrera_b );

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir( 'GET', '/api/carreras.cgi' );

    check( $status == 200, 'GET carreras responde 200', "HTTP $status" );
    check( ref($cuerpo) eq 'HASH' && $cuerpo->{ok} && ref( $cuerpo->{data} ) eq 'ARRAY',
        'La respuesta trae el sobre {ok, data}' );

    if ( ref( $cuerpo->{data} ) eq 'ARRAY' && @{ $cuerpo->{data} } >= 2 ) {
        $carrera_a = $cuerpo->{data}[0]{id};
        $carrera_b = $cuerpo->{data}[1]{id};
    }

    my ($con_acento) = grep { $_->{nombre} =~ /[áéíóúñ]/ } @{ $cuerpo->{data} || [] };
    check( $con_acento, 'Los acentos llegan bien por HTTP',
        $con_acento ? $con_acento->{nombre} : undef );
}

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir( 'POST', '/api/carreras.cgi', {} );
    check( $status == 405 && codigo_error($cuerpo) eq 'METODO_NO_PERMITIDO',
        'POST a un endpoint de solo lectura da 405', "HTTP $status" );
}

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir(
        'POST',
        '/api/inscripciones.cgi',
        {   nombre       => 'Ana Pérez',
            email        => $EMAIL,
            telefono     => '11-5566-7788',
            nacionalidad => 'Argentina',
            carrera_id   => $carrera_a,
        }
    );

    check( $status == 201, 'Inscripción válida responde 201', "HTTP $status" );
    check( $cuerpo->{data}{alumno_nuevo}, 'Y marca que el alumno es nuevo' );
}

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir(
        'POST',
        '/api/inscripciones.cgi',
        { nombre => 'Ana Pérez', email => $EMAIL, carrera_id => $carrera_a }
    );

    check( $status == 409 && codigo_error($cuerpo) eq 'ALUMNO_YA_INSCRIPTO',
        'Repetir la misma carrera da 409', "HTTP $status" );
}

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir(
        'POST',
        '/api/inscripciones.cgi',
        { nombre => 'Ana Pérez', email => $EMAIL, carrera_id => $carrera_b }
    );

    check( $status == 201 && !$cuerpo->{data}{alumno_nuevo},
        'Otra carrera, mismo email: 201 reutilizando ficha', "HTTP $status" );
}

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo )
        = pedir( 'POST', '/api/inscripciones.cgi', { nombre => '', email => 'roto' } );

    check( $status == 400 && codigo_error($cuerpo) eq 'VALIDACION',
        'Datos inválidos dan 400', "HTTP $status" );
    check( ref( $cuerpo->{error}{campos} ) eq 'HASH',
        'Y el error detalla los campos',
        join( ', ', sort keys %{ $cuerpo->{error}{campos} || {} } ) );
}

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir( 'POST', '/api/inscripciones.cgi', 'esto no es json' );
    check( $status == 400 && codigo_error($cuerpo) eq 'VALIDACION',
        'Cuerpo que no es JSON da 400', "HTTP $status" );
}

print "\n--- Los archivos internos no se sirven ---\n";

# ---------------------------------------------------------------------
# Solo public/ y admin/ estan publicados. Nada de lo demas deberia
# tener una URL, en especial config/app.conf que lleva la contrasena.
for my $ruta ( '/config/app.conf', '/lib/UP/DB.pm', '/database/00_crear_base.sql',
    '/../config/app.conf' )
{
    my ( $status, undef, $crudo ) = pedir( 'GET', $ruta );
    my $filtrado = defined $crudo && $crudo =~ /db_pass|DBI|CREATE ROLE/;

    check( $status >= 400 && !$filtrado, "No se puede leer $ruta", "HTTP $status" );
}

print "\n--- Parte privada (ABM) ---\n";

my ( $alumno_id, $alumno2_id, $inscripcion_id );

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir( 'GET', '/admin/api/alumnos.cgi' );

    check( $status == 200 && ref( $cuerpo->{data} ) eq 'ARRAY',
        'GET alumnos lista', "HTTP $status" );

    my ($nuestro) = grep { ( $_->{email} // '' ) eq $EMAIL } @{ $cuerpo->{data} || [] };
    $alumno_id = $nuestro->{id} if $nuestro;

    check( $nuestro && @{ $nuestro->{carreras} } == 2,
        'El listado trae las carreras de cada alumno',
        $nuestro ? scalar( @{ $nuestro->{carreras} } ) : undef );
}

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir( 'GET', "/admin/api/alumnos.cgi?id=$alumno_id" );
    check( $status == 200 && $cuerpo->{data}{email} eq $EMAIL,
        'GET de una ficha puntual', "HTTP $status" );
}

{
    my ( $status, $cuerpo ) = pedir( 'GET', '/admin/api/alumnos.cgi?id=999999' );
    check( $status == 404 && codigo_error($cuerpo) eq 'NO_ENCONTRADO',
        'Ficha inexistente da 404', "HTTP $status" );
}

{
    my ( $status, $cuerpo ) = pedir( 'GET', '/admin/api/alumnos.cgi?id=no-es-un-id' );
    check( $status == 404, 'Id con formato inválido da 404', "HTTP $status" );
}

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir(
        'POST',
        '/admin/api/alumnos.cgi',
        {   nombre       => 'Bruno Ñáñez',
            email        => $EMAIL2,
            telefono     => '11-1111-2222',
            nacionalidad => 'Paraguaya',
            carrera_id   => $carrera_a,
        }
    );
    $alumno2_id = $cuerpo->{data}{alumno_id};
    check( $status == 201 && $alumno2_id, 'Alta desde el ABM da 201', "HTTP $status" );
}

{
    my ( $status, $cuerpo ) = pedir(
        'POST',
        '/admin/api/alumnos.cgi',
        { nombre => 'Otro', email => $EMAIL2, carrera_id => $carrera_a }
    );
    check( $status == 409 && codigo_error($cuerpo) eq 'EMAIL_DUPLICADO',
        'Alta con email repetido da 409', "HTTP $status" );
}

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir(
        'PUT',
        "/admin/api/alumnos.cgi?id=$alumno2_id",
        {   nombre       => 'Bruno Ñáñez',
            email        => $EMAIL2,
            telefono     => '11-3333-4444',
            nacionalidad => 'Uruguaya',
        }
    );
    check( $status == 200, 'PUT modifica', "HTTP $status" );

    my ( undef, $ficha ) = pedir( 'GET', "/admin/api/alumnos.cgi?id=$alumno2_id" );
    check( $ficha->{data}{nacionalidad} eq 'Uruguaya' && $ficha->{data}{nombre} eq 'Bruno Ñáñez',
        'El cambio se guardó, con acentos intactos', $ficha->{data}{nombre} );
}

{
    my ( $status, $cuerpo ) = pedir(
        'PUT',
        "/admin/api/alumnos.cgi?id=$alumno2_id",
        { nombre => 'Bruno', email => $EMAIL }
    );
    check( $status == 409 && codigo_error($cuerpo) eq 'EMAIL_DUPLICADO',
        'PUT con el email de otro da 409', "HTTP $status" );
}

# ---------------------------------------------------------------------
{
    my ( $status, $cuerpo ) = pedir( 'POST', '/admin/api/inscripciones.cgi',
        { alumno_id => $alumno2_id, carrera_id => $carrera_b } );
    $inscripcion_id = $cuerpo->{data}{inscripcion_id};
    check( $status == 201 && $inscripcion_id, 'Asignar una carrera da 201', "HTTP $status" );
}

{
    my ( $status, $cuerpo ) = pedir( 'POST', '/admin/api/inscripciones.cgi',
        { alumno_id => $alumno2_id, carrera_id => $carrera_b } );
    check( $status == 409 && codigo_error($cuerpo) eq 'ALUMNO_YA_INSCRIPTO',
        'Asignar la misma carrera da 409', "HTTP $status" );
}

{
    my ( $status, undef )
        = pedir( 'DELETE', "/admin/api/inscripciones.cgi?id=$inscripcion_id" );
    check( $status == 200, 'DELETE quita la inscripción', "HTTP $status" );
}

{
    my ( $status, $cuerpo )
        = pedir( 'DELETE', '/admin/api/inscripciones.cgi?id=999999' );
    check( $status == 404 && codigo_error($cuerpo) eq 'NO_ENCONTRADO',
        'DELETE de algo inexistente da 404', "HTTP $status" );
}

print "\n--- Limpieza ---\n";

# ---------------------------------------------------------------------
for my $id ( grep {defined} $alumno_id, $alumno2_id ) {
    my ($status) = pedir( 'DELETE', "/admin/api/alumnos.cgi?id=$id" );
    check( $status == 200, "Baja del alumno $id", "HTTP $status" );
}

print "\n";
if ($fallos) {
    print "RESULTADO: $fallos de $paso chequeos fallaron.\n";
    exit 1;
}
print "RESULTADO: los $paso chequeos pasaron.\n";
exit 0;
