#!/usr/bin/env perl

# =====================================================================
# Prueba de la capa de acceso a datos, sin pasar por HTTP.
#
#     perl tests/prueba_capa_datos.pl
#
# Trabaja contra la base real y limpia lo que crea. Si algo queda a
# medias, el ultimo chequeo lo detecta.
# =====================================================================

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../backend";

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

use UP::DB;
use UP::Repo::Carrera;
use UP::Repo::Alumno;
use UP::Repo::Inscripcion;

my $fallos = 0;
my $paso   = 0;

sub check {
    my ( $condicion, $descripcion, $detalle ) = @_;
    $paso++;
    if ($condicion) {
        printf "%2d. %-52s OK%s\n", $paso, $descripcion,
            ( defined $detalle ? "  ($detalle)" : '' );
    }
    else {
        $fallos++;
        printf "%2d. %-52s FALLO%s\n", $paso, $descripcion,
            ( defined $detalle ? "  ($detalle)" : '' );
    }
    return;
}

# Email propio de la prueba, para no pisar datos reales.
my $EMAIL  = 'prueba.capa.datos@up.edu.ar';
my $NOMBRE = 'Ana Pérez Ñandú';    # con tildes y enie a proposito

my $dbh = UP::DB->handle;
print "Conectado a la base.\n\n";

# Por si una corrida anterior quedo a mitad de camino.
{
    my $viejo = UP::Repo::Alumno::buscar_por_email( $dbh, $EMAIL );
    UP::Repo::Alumno::borrar( $dbh, $viejo->{id} ) if $viejo;
}

# Foto del estado ANTES de empezar.
#
# Al final se compara contra esta foto, en vez de exigir que las tablas
# queden vacias. Lo que hay que verificar no es que la base este vacia,
# sino que esta prueba no deje nada atras: exigir cero daria rojo con
# solo tener datos reales cargados.
my ($alumnos_antes) = $dbh->selectrow_array('SELECT count(*) FROM alumno');
my ($inscs_antes)   = $dbh->selectrow_array('SELECT count(*) FROM inscripcion');

my ( $alumno_id, $carrera_a, $carrera_b, $insc_a, $insc_b );

eval {
    # -----------------------------------------------------------------
    my $carreras = UP::Repo::Carrera::listar( $dbh, solo_activas => 1 );
    check( @$carreras >= 2, 'Listar carreras activas', scalar(@$carreras) . ' encontradas' );
    ( $carrera_a, $carrera_b ) = ( $carreras->[0]{id}, $carreras->[1]{id} );

    my ($con_acento) = grep { $_->{nombre} =~ /[áéíóúñÁÉÍÓÚÑ]/ } @$carreras;
    check( $con_acento, 'Los acentos sobreviven el viaje desde la base',
        $con_acento ? $con_acento->{nombre} : 'ninguna carrera con acentos' );

    # -----------------------------------------------------------------
    $alumno_id = UP::Repo::Alumno::insertar(
        $dbh,
        {   nombre       => $NOMBRE,
            email        => $EMAIL,
            telefono     => '11-5566-7788',
            nacionalidad => 'Argentina',
        }
    );
    check( $alumno_id, 'Alta de alumno', "id $alumno_id" );

    # -----------------------------------------------------------------
    my $leido = UP::Repo::Alumno::buscar_por_id( $dbh, $alumno_id );
    check( $leido && $leido->{nombre} eq $NOMBRE,
        'El nombre con tildes vuelve identico', $leido->{nombre} );

    # -----------------------------------------------------------------
    my $por_email = UP::Repo::Alumno::buscar_por_email( $dbh, uc($EMAIL) );
    check( $por_email && $por_email->{id} == $alumno_id,
        'Busqueda por email ignora mayusculas' );

    # -----------------------------------------------------------------
    check( !UP::Repo::Inscripcion::existe( $dbh, $alumno_id, $carrera_a ),
        'Todavia no esta inscripto a la carrera A' );

    $insc_a = UP::Repo::Inscripcion::insertar( $dbh, $alumno_id, $carrera_a );
    check( $insc_a, 'Inscripcion a la carrera A', "id $insc_a" );

    check( UP::Repo::Inscripcion::existe( $dbh, $alumno_id, $carrera_a ),
        'Ahora si figura inscripto a la carrera A' );

    # -----------------------------------------------------------------
    $insc_b = UP::Repo::Inscripcion::insertar( $dbh, $alumno_id, $carrera_b );
    check( $insc_b, 'Inscripcion a una segunda carrera (N:M)', "id $insc_b" );

    my $suyas = UP::Repo::Inscripcion::listar_por_alumno( $dbh, $alumno_id );
    check( @$suyas == 2, 'Listar inscripciones del alumno', scalar(@$suyas) );

    # -----------------------------------------------------------------
    my $duplicada = eval {
        UP::Repo::Inscripcion::insertar( $dbh, $alumno_id, $carrera_a );
        1;
    };
    my $sqlstate = $dbh->state;
    check( !$duplicada && $sqlstate eq '23505',
        'Inscripcion repetida rechazada por la base', "SQLSTATE $sqlstate" );

    # -----------------------------------------------------------------
    my $listado = UP::Repo::Alumno::listar($dbh);
    my ($nuestro) = grep { $_->{id} == $alumno_id } @$listado;
    check(
        $nuestro && ref( $nuestro->{carreras} ) eq 'ARRAY' && @{ $nuestro->{carreras} } == 2,
        'Listado trae las carreras ya decodificadas',
        $nuestro ? scalar( @{ $nuestro->{carreras} } ) . ' carreras' : 'no aparecio'
    );
    check(
        $nuestro && defined $nuestro->{carreras}[0]{carrera_nombre},
        'Cada carrera del listado trae id y nombre',
        $nuestro ? $nuestro->{carreras}[0]{carrera_nombre} : undef
    );

    # -----------------------------------------------------------------
    my $filas = UP::Repo::Alumno::actualizar(
        $dbh,
        $alumno_id,
        {   nombre       => 'Ana Pérez Modificada',
            email        => $EMAIL,
            telefono     => '11-0000-0000',
            nacionalidad => 'Uruguaya',
        }
    );
    my $tras_update = UP::Repo::Alumno::buscar_por_id( $dbh, $alumno_id );
    check( $filas == 1 && $tras_update->{nacionalidad} eq 'Uruguaya',
        'Modificacion de alumno', "$filas fila" );

    # -----------------------------------------------------------------
    my $borradas = UP::Repo::Inscripcion::borrar( $dbh, $insc_b );
    check( $borradas == 1, 'Baja de una inscripcion puntual' );

    # -----------------------------------------------------------------
    my $en_carrera = UP::Repo::Inscripcion::contar_por_carrera( $dbh, $carrera_a );
    check( $en_carrera >= 1, 'Contar inscriptos por carrera', $en_carrera );

    1;
} or do {
    my $error = $@ // 'error desconocido';
    $error =~ s/\s+$//;
    print "\nEXCEPCION: $error\n\n";
    $fallos++;
};

# ---------------------------------------------------------------------
# Baja del alumno: sus inscripciones se van solas por el CASCADE.
# ---------------------------------------------------------------------
if ($alumno_id) {
    my $borrado = UP::Repo::Alumno::borrar( $dbh, $alumno_id );
    check( $borrado == 1, 'Baja del alumno' );

    my $restantes = UP::Repo::Inscripcion::listar_por_alumno( $dbh, $alumno_id );
    check( @$restantes == 0, 'El CASCADE se llevo sus inscripciones' );
}

# ---------------------------------------------------------------------
# La transaccion tiene que revertir todo si algo falla en el medio.
# ---------------------------------------------------------------------
{
    my $email_tx = 'prueba.rollback@up.edu.ar';

    eval {
        UP::DB->transaccion(
            sub {
                my ($dbh_tx) = @_;
                UP::Repo::Alumno::insertar( $dbh_tx,
                    { nombre => 'Se Revierte', email => $email_tx } );
                die "error simulado a mitad de la transaccion\n";
            }
        );
        1;
    };

    my $quedo = UP::Repo::Alumno::buscar_por_email( $dbh, $email_tx );
    check( !$quedo, 'Rollback: el alta revertida no quedo en la base' );
}

# ---------------------------------------------------------------------
{
    my ($alumnos_despues) = $dbh->selectrow_array('SELECT count(*) FROM alumno');
    my ($inscs_despues)   = $dbh->selectrow_array('SELECT count(*) FROM inscripcion');

    check(
        $alumnos_despues == $alumnos_antes && $inscs_despues == $inscs_antes,
        'La prueba no dejo datos atras',
        "alumnos $alumnos_antes -> $alumnos_despues, inscripciones $inscs_antes -> $inscs_despues"
    );
}

UP::DB->desconectar;

print "\n";
if ($fallos) {
    print "RESULTADO: $fallos de $paso chequeos fallaron.\n";
    exit 1;
}
print "RESULTADO: los $paso chequeos pasaron.\n";
exit 0;
