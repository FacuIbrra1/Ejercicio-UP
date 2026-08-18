package UP::Service::Alumno;

# =====================================================================
# Reglas de negocio del ABM de alumnos: alta, baja, modificacion y
# consulta.
#
# La inscripcion a carreras vive en UP::Service::Inscripcion.
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

# ---------------------------------------------------------------------
# Listado completo, cada alumno con sus carreras.
# ---------------------------------------------------------------------
sub listar {
    my ($class) = @_;
    return UP::Repo::Alumno::listar( UP::DB->handle );
}

# ---------------------------------------------------------------------
# Ficha de un alumno con el detalle de sus inscripciones.
# ---------------------------------------------------------------------
sub obtener {
    my ( $class, $id_crudo ) = @_;

    my $id = UP::Service::Validacion::validar_id($id_crudo);
    UP::Error->lanzar( 'NO_ENCONTRADO', 'El alumno no existe.' )
        unless defined $id;

    my $dbh = UP::DB->handle;

    my $alumno = UP::Repo::Alumno::buscar_por_id( $dbh, $id );
    UP::Error->lanzar( 'NO_ENCONTRADO', 'El alumno no existe.' )
        unless $alumno;

    $alumno->{carreras} = UP::Repo::Inscripcion::listar_por_alumno( $dbh, $id );

    return $alumno;
}

# ---------------------------------------------------------------------
# Alta desde el ABM.
#
# Pide una carrera igual que el formulario publico. La consigna dice
# que hay que asignarle una carrera a cada alumno, asi que no se puede
# crear uno suelto.
# ---------------------------------------------------------------------
sub crear {
    my ( $class, $datos ) = @_;

    my $limpios = UP::Service::Validacion::validar_alumno( $datos, requiere_carrera => 1 );

    return UP::DB->transaccion(
        sub {
            my ($dbh) = @_;

            my $carrera = UP::Repo::Carrera::buscar_por_id( $dbh, $limpios->{carrera_id} );
            UP::Error->lanzar( 'CARRERA_INVALIDA',
                'La carrera elegida no está disponible.' )
                if !$carrera || !$carrera->{activa};

            # Chequeo previo para dar un mensaje claro; la garantia
            # contra duplicados es el indice unico.
            if ( UP::Repo::Alumno::buscar_por_email( $dbh, $limpios->{email} ) ) {
                UP::Error->lanzar( 'EMAIL_DUPLICADO',
                    "Ya existe un alumno con el email $limpios->{email}." );
            }

            my $alumno_id;

            unless (
                eval {
                    $alumno_id = UP::Repo::Alumno::insertar( $dbh, $limpios );
                    1;
                }
                )
            {
                UP::Error->desde_sqlstate(
                    $dbh->state, $@,
                    {   '23505' => [ 'EMAIL_DUPLICADO',
                            "Ya existe un alumno con el email $limpios->{email}." ],
                        '23514' => [ 'VALIDACION', 'Hay datos que revisar.' ],
                    }
                );
            }

            my $inscripcion_id
                = UP::Repo::Inscripcion::insertar( $dbh, $alumno_id, $carrera->{id} );

            return {
                alumno_id      => $alumno_id,
                inscripcion_id => $inscripcion_id,
                carrera        => $carrera->{nombre},
            };
        }
    );
}

# ---------------------------------------------------------------------
# Modificacion de los datos de un alumno.
#
# No toca sus inscripciones: para eso estan asignar y quitar en
# UP::Service::Inscripcion.
# ---------------------------------------------------------------------
sub modificar {
    my ( $class, $id_crudo, $datos ) = @_;

    my $id = UP::Service::Validacion::validar_id($id_crudo);
    UP::Error->lanzar( 'NO_ENCONTRADO', 'El alumno no existe.' )
        unless defined $id;

    my $limpios = UP::Service::Validacion::validar_alumno($datos);

    return UP::DB->transaccion(
        sub {
            my ($dbh) = @_;

            UP::Error->lanzar( 'NO_ENCONTRADO', 'El alumno no existe.' )
                unless UP::Repo::Alumno::buscar_por_id( $dbh, $id );

            # Se excluye su propio id: si no, nadie podria guardar una
            # edicion en la que no cambio el email.
            if ( UP::Repo::Alumno::buscar_por_email_excepto( $dbh, $limpios->{email}, $id ) ) {
                UP::Error->lanzar( 'EMAIL_DUPLICADO',
                    "Ya existe otro alumno con el email $limpios->{email}." );
            }

            unless (
                eval {
                    UP::Repo::Alumno::actualizar( $dbh, $id, $limpios );
                    1;
                }
                )
            {
                UP::Error->desde_sqlstate(
                    $dbh->state, $@,
                    {   '23505' => [ 'EMAIL_DUPLICADO',
                            "Ya existe otro alumno con el email $limpios->{email}." ],
                        '23514' => [ 'VALIDACION', 'Hay datos que revisar.' ],
                    }
                );
            }

            return { alumno_id => $id };
        }
    );
}

# ---------------------------------------------------------------------
# Baja. Las inscripciones del alumno se borran solas por el ON DELETE
# CASCADE de la clave foranea.
# ---------------------------------------------------------------------
sub eliminar {
    my ( $class, $id_crudo ) = @_;

    my $id = UP::Service::Validacion::validar_id($id_crudo);
    UP::Error->lanzar( 'NO_ENCONTRADO', 'El alumno no existe.' )
        unless defined $id;

    return UP::DB->transaccion(
        sub {
            my ($dbh) = @_;

            my $borrados = UP::Repo::Alumno::borrar( $dbh, $id );

            UP::Error->lanzar( 'NO_ENCONTRADO', 'El alumno no existe.' )
                unless $borrados;

            return { alumno_id => $id };
        }
    );
}

1;
