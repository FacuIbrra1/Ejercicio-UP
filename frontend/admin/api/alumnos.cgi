#!C:/Strawberry/perl/bin/perl.exe

# =====================================================================
# /up/admin/api/alumnos.cgi        ABM de alumnos
#
# Zona privada, protegida por el .htaccess de admin/. Este script no
# chequea credenciales: si el pedido no esta autenticado, Apache ni
# siquiera lo ejecuta.
#
#   GET     ?id=N   ficha de un alumno con sus inscripciones
#   GET             listado completo
#   POST            alta          { nombre, email, telefono, nacionalidad, carrera_id }
#   PUT     ?id=N   modificacion  { nombre, email, telefono, nacionalidad }
#   DELETE  ?id=N   baja
# =====================================================================

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;

use lib File::Spec->catdir( dirname(__FILE__), File::Spec->updir, File::Spec->updir, File::Spec->updir, 'backend' );

use UP::Web::Api;
use UP::Service::Alumno;

UP::Web::Api->despachar(
    {   GET => sub {
            my $id = UP::Web::Api->parametro('id');

            return UP::Service::Alumno->obtener($id) if defined $id && $id ne '';
            return UP::Service::Alumno->listar;
        },

        POST => sub {
            my $datos = UP::Web::Api->cuerpo_json;

            my $resultado = UP::Service::Alumno->crear($datos);

            UP::Web::Api->estado(201);
            return $resultado;
        },

        PUT => sub {
            my $datos = UP::Web::Api->cuerpo_json;

            return UP::Service::Alumno->modificar( UP::Web::Api->parametro('id'), $datos );
        },

        DELETE => sub {
            return UP::Service::Alumno->eliminar( UP::Web::Api->parametro('id') );
        },
    }
);
