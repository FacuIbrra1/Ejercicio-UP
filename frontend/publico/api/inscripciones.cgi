#!C:/Strawberry/perl/bin/perl.exe

# =====================================================================
# POST /up/api/inscripciones.cgi
#
# Alta desde el formulario publico. Endpoint abierto.
#
# Cuerpo esperado:
#   { nombre, email, telefono, nacionalidad, carrera_id }
#
# Respuestas:
#   201  inscripcion creada
#   400  datos invalidos (VALIDACION) o carrera no disponible
#   409  ya hay una inscripcion de ese email a esa carrera
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

            my $resultado = UP::Service::Inscripcion->inscribir($datos);

            UP::Web::Api->estado(201);
            return $resultado;
        },
    }
);
