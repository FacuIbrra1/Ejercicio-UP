#!/usr/bin/env perl

# =====================================================================
# Prueba de la capa de negocio, sin pasar por HTTP.
#
#     perl tests/prueba_negocio.pl
#
# Verifica que cada regla devuelva su codigo de error correcto, que es
# lo que despues traduce la capa web a un status HTTP.
#
# Trabaja contra la base real y limpia lo que crea.
# =====================================================================

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../backend";

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

use UP::DB;
use UP::Error;
use UP::Repo::Alumno;
use UP::Repo::Carrera;
use UP::Service::Alumno;
use UP::Service::Inscripcion;

my $fallos = 0;
my $paso   = 0;

sub check {
    my ( $condicion, $descripcion, $detalle ) = @_;
    $paso++;
    printf "%2d. %-54s %s%s\n", $paso, $descripcion,
        ( $condicion ? 'OK' : 'FALLO' ),
        ( defined $detalle ? "  ($detalle)" : '' );
    $fallos++ unless $condicion;
    return;
}

# Corre $codigo y devuelve el codigo de error de negocio que lanzo,
# 'SIN_ERROR' si no lanzo nada, o 'EXCEPCION: ...' si lo que salio no
# era un error de negocio. Esa distincion importa: un bug no puede
# pasar por un error esperado.
sub codigo_de_error {
    my ($codigo) = @_;

    my $resultado = eval { $codigo->(); 1 };
    return 'SIN_ERROR' if $resultado;

    my $error = $@;
    return $error->codigo if UP::Error->es($error);

    my $texto = "$error";
    $texto =~ s/\s+/ /g;
    return "EXCEPCION: $texto";
}

my $EMAIL  = 'prueba.negocio@up.edu.ar';
my $EMAIL2 = 'prueba.negocio.dos@up.edu.ar';

my $dbh = UP::DB->handle;

# Limpieza defensiva por si una corrida anterior quedo a medias.
for my $mail ( $EMAIL, $EMAIL2 ) {
    my $viejo = UP::Repo::Alumno::buscar_por_email( $dbh, $mail );
    UP::Repo::Alumno::borrar( $dbh, $viejo->{id} ) if $viejo;
}

# Foto del estado ANTES de empezar.
#
# Al final se compara contra esta foto, en vez de exigir que las tablas
# queden vacias. Que la base este vacia no es lo que hay que verificar:
# lo que importa es que esta prueba no deje nada atras. Si se exigiera
# cero, la suite daria rojo con solo tener datos reales cargados, que
# es justo lo que pasa despues de usar la aplicacion a mano.
#
# Se toma despues de la limpieza defensiva de arriba, para que restos
# de una corrida anterior no entren como parte del punto de partida.
my ($alumnos_antes) = $dbh->selectrow_array('SELECT count(*) FROM alumno');
my ($inscs_antes)   = $dbh->selectrow_array('SELECT count(*) FROM inscripcion');

my $carreras = UP::Repo::Carrera::listar( $dbh, solo_activas => 1 );
my ( $carrera_a, $carrera_b ) = ( $carreras->[0]{id}, $carreras->[1]{id} );

my $alumno_id;

print "Carrera A: $carreras->[0]{nombre}   Carrera B: $carreras->[1]{nombre}\n\n";
print "--- Validacion ---\n";

# ---------------------------------------------------------------------
check(
    codigo_de_error( sub { UP::Service::Inscripcion->inscribir( {} ) } ) eq 'VALIDACION',
    'Formulario vacío'
);

{
    my $campos = {};
    eval { UP::Service::Inscripcion->inscribir( {} ); 1 } or do {
        my $error = $@;
        $campos = $error->campos if UP::Error->es($error);
    };

    check(
        $campos->{nombre} && $campos->{email} && $campos->{carrera_id},
        'El error trae los tres campos faltantes juntos',
        join( ', ', sort keys %$campos )
    );
}

check(
    codigo_de_error(
        sub {
            UP::Service::Inscripcion->inscribir(
                { nombre => 'Test', email => 'no-es-email', carrera_id => $carrera_a } );
        }
    ) eq 'VALIDACION',
    'Email con formato inválido'
);

check(
    codigo_de_error(
        sub {
            UP::Service::Inscripcion->inscribir(
                {   nombre     => 'Test',
                    email      => $EMAIL,
                    telefono   => 'cuatro-cuatro-cuatro',
                    carrera_id => $carrera_a
                }
            );
        }
    ) eq 'VALIDACION',
    'Teléfono con letras'
);

check(
    codigo_de_error(
        sub {
            UP::Service::Inscripcion->inscribir(
                { nombre => 'Test', email => $EMAIL, carrera_id => 999999 } );
        }
    ) eq 'CARRERA_INVALIDA',
    'Carrera inexistente'
);

print "\n--- Inscripción pública ---\n";

# ---------------------------------------------------------------------
{
    my $r = UP::Service::Inscripcion->inscribir(
        {   nombre       => '  Ana   Pérez  ',       # espacios de sobra a proposito
            email        => $EMAIL,
            telefono     => '11-5566-7788',
            nacionalidad => 'Argentina',
            carrera_id   => $carrera_a,
        }
    );
    $alumno_id = $r->{alumno_id};

    check( $r->{alumno_id} && $r->{inscripcion_id} && $r->{alumno_nuevo},
        'Inscripción de un alumno nuevo', "alumno $r->{alumno_id}" );

    my $guardado = UP::Repo::Alumno::buscar_por_id( $dbh, $alumno_id );
    check( $guardado->{nombre} eq 'Ana Pérez',
        'Los espacios de más se normalizaron', "'$guardado->{nombre}'" );
}

check(
    codigo_de_error(
        sub {
            UP::Service::Inscripcion->inscribir(
                { nombre => 'Ana Pérez', email => uc($EMAIL), carrera_id => $carrera_a } );
        }
    ) eq 'ALUMNO_YA_INSCRIPTO',
    'Misma persona, misma carrera (aunque cambie el case)'
);

# ---------------------------------------------------------------------
{
    my $r = UP::Service::Inscripcion->inscribir(
        { nombre => 'Ana Pérez', email => $EMAIL, carrera_id => $carrera_b } );

    check( $r->{inscripcion_id} && !$r->{alumno_nuevo},
        'Misma persona, otra carrera: reutiliza la ficha', "alumno $r->{alumno_id}" );

    check( $r->{alumno_id} == $alumno_id, 'Y es el mismo alumno, no uno nuevo' );
}

{
    my $ficha = UP::Service::Alumno->obtener($alumno_id);
    check( @{ $ficha->{carreras} } == 2, 'La ficha muestra sus dos carreras' );

    # El formulario publico no permite pisar datos de alguien existente.
    UP::Service::Inscripcion->inscribir(
        {   nombre     => 'Nombre Falso',
            email      => $EMAIL,
            telefono   => '11-9999-9999',
            carrera_id => $carreras->[2]{id},
        }
    );
    my $tras = UP::Repo::Alumno::buscar_por_id( $dbh, $alumno_id );
    check( $tras->{nombre} eq 'Ana Pérez' && $tras->{telefono} eq '11-5566-7788',
        'Una inscripción nueva no pisa los datos existentes', $tras->{nombre} );
}

print "\n--- ABM ---\n";

# ---------------------------------------------------------------------
check(
    codigo_de_error(
        sub {
            UP::Service::Alumno->crear(
                { nombre => 'Otro', email => $EMAIL, carrera_id => $carrera_a } );
        }
    ) eq 'EMAIL_DUPLICADO',
    'Alta con un email ya usado'
);

check(
    codigo_de_error( sub { UP::Service::Alumno->obtener(999999) } ) eq 'NO_ENCONTRADO',
    'Consulta de un alumno inexistente'
);

check(
    codigo_de_error( sub { UP::Service::Alumno->obtener('no-es-un-id') } ) eq 'NO_ENCONTRADO',
    'Id con formato inválido'
);

check(
    codigo_de_error( sub { UP::Service::Alumno->eliminar(999999) } ) eq 'NO_ENCONTRADO',
    'Baja de un alumno inexistente'
);

# ---------------------------------------------------------------------
my $alumno2_id;
{
    my $r = UP::Service::Alumno->crear(
        {   nombre       => 'Bruno Ñáñez',
            email        => $EMAIL2,
            telefono     => '11-1111-2222',
            nacionalidad => 'Paraguaya',
            carrera_id   => $carrera_a,
        }
    );
    $alumno2_id = $r->{alumno_id};
    check( $alumno2_id, 'Alta desde el ABM', "id $alumno2_id" );
}

check(
    codigo_de_error(
        sub {
            UP::Service::Alumno->modificar( $alumno2_id,
                { nombre => 'Bruno', email => $EMAIL } );
        }
    ) eq 'EMAIL_DUPLICADO',
    'Modificar poniéndole el email de otro'
);

{
    UP::Service::Alumno->modificar(
        $alumno2_id,
        {   nombre       => 'Bruno Ñáñez',
            email        => $EMAIL2,             # su propio email, sin cambios
            telefono     => '11-3333-4444',
            nacionalidad => 'Uruguaya',
        }
    );
    my $tras = UP::Repo::Alumno::buscar_por_id( $dbh, $alumno2_id );
    check( $tras->{nacionalidad} eq 'Uruguaya',
        'Modificar sin tocar el email propio', $tras->{nacionalidad} );
}

check(
    codigo_de_error(
        sub { UP::Service::Inscripcion->asignar( $alumno2_id, $carrera_a ) }
    ) eq 'ALUMNO_YA_INSCRIPTO',
    'Asignarle una carrera que ya tiene'
);

{
    my $r = UP::Service::Inscripcion->asignar( $alumno2_id, $carrera_b );
    check( $r->{inscripcion_id}, 'Asignarle una carrera nueva', $r->{carrera} );

    my $quitada = UP::Service::Inscripcion->quitar( $r->{inscripcion_id} );
    check( $quitada->{inscripcion_id} == $r->{inscripcion_id}, 'Quitarle esa carrera' );
}

check(
    codigo_de_error( sub { UP::Service::Inscripcion->quitar(999999) } ) eq 'NO_ENCONTRADO',
    'Quitar una inscripción inexistente'
);

check(
    codigo_de_error( sub { UP::Service::Inscripcion->asignar( 999999, $carrera_a ) } )
        eq 'NO_ENCONTRADO',
    'Asignarle una carrera a un alumno inexistente'
);

print "\n--- Limpieza ---\n";

# ---------------------------------------------------------------------
for my $id ( grep {defined} $alumno_id, $alumno2_id ) {
    UP::Service::Alumno->eliminar($id);
}

{
    my ($alumnos_despues) = $dbh->selectrow_array('SELECT count(*) FROM alumno');
    my ($inscs_despues)   = $dbh->selectrow_array('SELECT count(*) FROM inscripcion');

    check(
        $alumnos_despues == $alumnos_antes && $inscs_despues == $inscs_antes,
        'La prueba no dejó datos atrás',
        "alumnos $alumnos_antes → $alumnos_despues, inscripciones $inscs_antes → $inscs_despues"
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
