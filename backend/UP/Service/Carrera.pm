package UP::Service::Carrera;

# =====================================================================
# Carreras.
#
# Es casi un pasamanos al repositorio: no hay reglas de negocio
# sobre carreras porque el ejercicio no pide un ABM de carreras.
# Existe igual para que la regla de capas no tenga excepciones: los
# .cgi hablan siempre con un service, nunca con un repositorio. Si
# manana aparece una regla (cupos, fechas de inscripcion), tiene donde
# entrar sin tocar la capa web.
# =====================================================================

use strict;
use warnings;

use UP::DB;
use UP::Repo::Carrera;

# ---------------------------------------------------------------------
# Las que se ofrecen en el formulario publico.
# ---------------------------------------------------------------------
sub listar_activas {
    my ($class) = @_;
    return UP::Repo::Carrera::listar( UP::DB->handle, solo_activas => 1 );
}

# ---------------------------------------------------------------------
# Todas, incluidas las dadas de baja. Lo usa el ABM, que necesita poder
# mostrar la carrera de un alumno aunque ya no se ofrezca.
# ---------------------------------------------------------------------
sub listar_todas {
    my ($class) = @_;
    return UP::Repo::Carrera::listar( UP::DB->handle );
}

1;
