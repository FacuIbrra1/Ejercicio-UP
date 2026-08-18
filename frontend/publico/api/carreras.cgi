#!C:/Strawberry/perl/bin/perl.exe

# =====================================================================
# GET /up/api/carreras.cgi
#
# Carreras disponibles para el formulario publico. Endpoint abierto.
# =====================================================================

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;

# Se resuelve desde __FILE__ y no desde el directorio de trabajo:
# Apache no garantiza cual es el cwd de un CGI.
use lib File::Spec->catdir( dirname(__FILE__), File::Spec->updir, File::Spec->updir, File::Spec->updir, 'backend' );

use UP::Web::Api;
use UP::Service::Carrera;

UP::Web::Api->despachar(
    {   GET => sub {
            return UP::Service::Carrera->listar_activas;
        },
    }
);
