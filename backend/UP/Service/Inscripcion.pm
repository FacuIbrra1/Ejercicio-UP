package UP::Service::Inscripcion;

# =====================================================================
# Reglas de negocio de la inscripcion.
#
# Los repositorios de UP::Repo::* son funciones que reciben un $dbh;
# los servicios son metodos de clase. La diferencia no es capricho: el
# servicio es el que abre y cierra la transaccion, y les pasa el mismo
# handle a todos los repos que participan. Quien mira el codigo sabe
# por la forma de la llamada en que capa esta parado.
# =====================================================================

use strict;
use warnings;
use utf8;

use UP::DB;
use UP::Error;
use UP::Repo::Alumno;
use UP::Repo::Carrera;
use UP::Repo::Inscripcion;
use UP::Service::Validacion;

# Los errores de la base se traducen a errores de negocio con
# UP::Error->desde_sqlstate, mirando el SQLSTATE y no el texto del
# mensaje: el texto cambia entre versiones de PostgreSQL y segun el
# idioma del servidor (el nuestro responde en castellano).

# =====================================================================
# Alta desde el formulario publico.
#
# Recibe los datos del alumno y la carrera elegida. Tres desenlaces:
#
#   - el email no existe        -> se crea el alumno y su inscripcion
#   - el email existe, carrera nueva -> se reutiliza la ficha y se
#                                       agrega la inscripcion
#   - el email existe, misma carrera -> ALUMNO_YA_INSCRIPTO
# =====================================================================
sub inscribir {
    my ( $class, $datos ) = @_;

    my $limpios = UP::Service::Validacion::validar_alumno( $datos, requiere_carrera => 1 );

    return UP::DB->transaccion(
        sub {
            my ($dbh) = @_;

            my $carrera = UP::Repo::Carrera::buscar_por_id( $dbh, $limpios->{carrera_id} );

            UP::Error->lanzar( 'CARRERA_INVALIDA',
                'La carrera elegida no está disponible.' )
                if !$carrera || !$carrera->{activa};

            my $existente = UP::Repo::Alumno::buscar_por_email( $dbh, $limpios->{email} );

            my $alumno_id;
            my $alumno_nuevo;

            if ($existente) {
                $alumno_id    = $existente->{id};
                $alumno_nuevo = 0;

                # Chequeo previo, solo para poder dar un mensaje que
                # nombre la carrera. La garantia real esta en la
                # constraint, mas abajo.
                if ( UP::Repo::Inscripcion::existe( $dbh, $alumno_id, $carrera->{id} ) ) {
                    UP::Error->lanzar( 'ALUMNO_YA_INSCRIPTO',
                        "Ya hay una inscripción a $carrera->{nombre} con el email $limpios->{email}."
                    );
                }

                # Los datos de contacto del alumno existente NO se
                # pisan con los que vengan del formulario. Es
                # deliberado: el formulario publico no pide ninguna
                # prueba de que sos el dueno de ese email, asi que
                # permitir la sobreescritura dejaria que cualquiera que
                # conozca tu direccion te cambie el telefono. Los datos
                # se corrigen desde el ABM.
            }
            else {
                $alumno_nuevo = 1;

                unless (
                    eval {
                        $alumno_id = UP::Repo::Alumno::insertar( $dbh, $limpios );
                        1;
                    }
                    )
                {
                    UP::Error->desde_sqlstate(
                        $dbh->state, $@,
                        {   # Otro proceso creo el mismo email entre el
                            # SELECT de arriba y este INSERT.
                            '23505' => [ 'EMAIL_DUPLICADO', 'Ya existe alguien registrado con ese email.' ],
                            '23514' => [ 'VALIDACION',      'Hay datos que revisar.' ],
                        }
                    );
                }
            }

            my $inscripcion_id;

            unless (
                eval {
                    $inscripcion_id
                        = UP::Repo::Inscripcion::insertar( $dbh, $alumno_id, $carrera->{id} );
                    1;
                }
                )
            {
                UP::Error->desde_sqlstate(
                    $dbh->state, $@,
                    {   '23505' => [ 'ALUMNO_YA_INSCRIPTO',
                            "Ya hay una inscripción a $carrera->{nombre} con el email $limpios->{email}." ],
                        '23503' => [ 'CARRERA_INVALIDA',
                            'La carrera elegida no está disponible.' ],
                    }
                );
            }

            return {
                alumno_id      => $alumno_id,
                inscripcion_id => $inscripcion_id,
                alumno_nuevo   => $alumno_nuevo,
                carrera        => $carrera->{nombre},
            };
        }
    );
}

# =====================================================================
# ABM: asignarle una carrera mas a un alumno que ya existe.
# =====================================================================
sub asignar {
    my ( $class, $alumno_id_crudo, $carrera_id_crudo ) = @_;

    my $alumno_id  = UP::Service::Validacion::validar_id($alumno_id_crudo);
    my $carrera_id = UP::Service::Validacion::validar_id($carrera_id_crudo);

    UP::Error->lanzar( 'VALIDACION', 'Hay datos que revisar.',
        campos => { alumno_id => 'Identificador de alumno inválido.' } )
        unless defined $alumno_id;

    UP::Error->lanzar( 'VALIDACION', 'Hay datos que revisar.',
        campos => { carrera_id => 'Elegí una carrera.' } )
        unless defined $carrera_id;

    return UP::DB->transaccion(
        sub {
            my ($dbh) = @_;

            my $alumno = UP::Repo::Alumno::buscar_por_id( $dbh, $alumno_id );
            UP::Error->lanzar( 'NO_ENCONTRADO', 'El alumno no existe.' )
                unless $alumno;

            my $carrera = UP::Repo::Carrera::buscar_por_id( $dbh, $carrera_id );
            UP::Error->lanzar( 'CARRERA_INVALIDA',
                'La carrera elegida no está disponible.' )
                if !$carrera || !$carrera->{activa};

            if ( UP::Repo::Inscripcion::existe( $dbh, $alumno_id, $carrera_id ) ) {
                UP::Error->lanzar( 'ALUMNO_YA_INSCRIPTO',
                    "$alumno->{nombre} ya está inscripto a $carrera->{nombre}." );
            }

            my $inscripcion_id;

            unless (
                eval {
                    $inscripcion_id
                        = UP::Repo::Inscripcion::insertar( $dbh, $alumno_id, $carrera_id );
                    1;
                }
                )
            {
                UP::Error->desde_sqlstate(
                    $dbh->state, $@,
                    {   '23505' => [ 'ALUMNO_YA_INSCRIPTO',
                            "$alumno->{nombre} ya está inscripto a $carrera->{nombre}." ],
                    }
                );
            }

            return {
                inscripcion_id => $inscripcion_id,
                alumno_id      => $alumno_id,
                carrera_id     => $carrera_id,
                carrera        => $carrera->{nombre},
            };
        }
    );
}

# =====================================================================
# ABM: quitarle una carrera a un alumno.
# =====================================================================
sub quitar {
    my ( $class, $inscripcion_id_crudo ) = @_;

    my $inscripcion_id = UP::Service::Validacion::validar_id($inscripcion_id_crudo);

    UP::Error->lanzar( 'NO_ENCONTRADO', 'La inscripción no existe.' )
        unless defined $inscripcion_id;

    return UP::DB->transaccion(
        sub {
            my ($dbh) = @_;

            my $borradas = UP::Repo::Inscripcion::borrar( $dbh, $inscripcion_id );

            UP::Error->lanzar( 'NO_ENCONTRADO', 'La inscripción no existe.' )
                unless $borradas;

            return { inscripcion_id => $inscripcion_id };
        }
    );
}

1;
