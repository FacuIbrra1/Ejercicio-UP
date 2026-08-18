#!C:/Strawberry/perl/bin/perl.exe

# =====================================================================
# /up/admin/api/inscripciones.cgi     asignar y quitar carreras
#
# Zona privada, protegida por el .htaccess de admin/.
#
#   POST            asignar una carrera   { alumno_id, carrera_id }
#   DELETE  ?id=N   quitar una inscripcion
#
# El id del DELETE es el de la INSCRIPCION, no el del alumno: es la
# fila concreta que relaciona a ese alumno con esa carrera.
# =====================================================================

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;

use lib File::Spec->catdir( dirname(__FILE__), File::Spec->updir, File::Spec->updir, File::Spec->updir, 'backend' );

use UP::Web::Api;
use UP::Service::Inscripcion;

UP::Web::Api->despachar(
    {   POST => sub {
            my $datos = UP::Web::Api->cuerpo_json;

            my $resultado = UP::Service::Inscripcion->asignar(
                $datos->{alumno_id},
                $datos->{carrera_id}
            );

            UP::Web::Api->estado(201);
            return $resultado;
        },

        DELETE => sub {
            return UP::Service::Inscripcion->quitar( UP::Web::Api->parametro('id') );
        },
    }
);
