#!C:/Strawberry/perl/bin/perl.exe

# =====================================================================
# GET /up/admin/api/carreras.cgi
#
# Zona privada, protegida por el .htaccess de admin/.
#
# Devuelve TODAS las carreras, incluidas las inactivas, a diferencia
# del endpoint publico: el ABM necesita poder mostrar la carrera de un
# alumno aunque ya no se este ofreciendo.
# =====================================================================

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;

use lib File::Spec->catdir( dirname(__FILE__), File::Spec->updir, File::Spec->updir, File::Spec->updir, 'backend' );

use UP::Web::Api;
use UP::Service::Carrera;

UP::Web::Api->despachar(
    {   GET => sub {
            return UP::Service::Carrera->listar_todas;
        },
    }
);
