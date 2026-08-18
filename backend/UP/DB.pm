package UP::DB;

# =====================================================================
# Conexion a PostgreSQL.
#
# Este modulo es el UNICO lugar del proyecto que sabe que la base es
# PostgreSQL y que se habla con DBI. Los repositorios reciben el handle
# ya armado; las capas de arriba ni siquiera lo ven.
# =====================================================================

use strict;
use warnings;

use DBI;
use UP::Config;

my $DBH;

# ---------------------------------------------------------------------
# Handle de conexion, reutilizado dentro del mismo proceso.
#
# Bajo CGI cada request es un proceso nuevo, asi que en la practica se
# conecta una vez por request. La cache igual sirve: evita reconectar
# cuando un service llama a varios repositorios.
# ---------------------------------------------------------------------
sub handle {
    return $DBH if $DBH && $DBH->ping;

    my $cfg = UP::Config->todo;

    my $dsn = sprintf(
        'dbi:Pg:dbname=%s;host=%s;port=%s',
        $cfg->{db_name}, $cfg->{db_host}, $cfg->{db_port}
    );

    $DBH = DBI->connect(
        $dsn,
        $cfg->{db_user},
        $cfg->{db_pass},
        {
            # Los errores se lanzan como excepciones y se manejan con
            # eval en la capa de negocio. Sin esto habria que chequear
            # el retorno de cada llamada a mano.
            RaiseError => 1,
            PrintError => 0,

            # Que no escriba nada en STDERR por su cuenta: bajo CGI eso
            # termina en el error_log de Apache mezclado con todo.
            PrintWarn => 0,

            AutoCommit => 1,

            # Los textos vienen y van en UTF-8 decodificado, para que
            # "Diseno Grafico" con tildes no se rompa.
            pg_enable_utf8 => 1,
        }
    );

    # Redundante con pg_enable_utf8 en la mayoria de los casos, pero en
    # Windows el client_encoding puede arrancar en WIN1252 segun el
    # locale del proceso, y ahi los acentos se corrompen en silencio.
    $DBH->do("SET client_encoding TO 'UTF8'");

    return $DBH;
}

# ---------------------------------------------------------------------
# Ejecuta $codigo dentro de una transaccion.
#
#   my $id = UP::DB->transaccion(sub {
#       my ($dbh) = @_;
#       ...
#       return $algo;
#   });
#
# Si $codigo muere, hace rollback y vuelve a lanzar el error original,
# para que la capa de negocio lo pueda clasificar.
#
# Si ya hay una transaccion abierta, se suma a ella en lugar de anidar
# (PostgreSQL no tiene transacciones anidadas reales, y abrir una
# segunda romperia el rollback de la primera).
# ---------------------------------------------------------------------
sub transaccion {
    my ( $class, $codigo ) = @_;

    my $dbh = $class->handle;

    return $codigo->($dbh) unless $dbh->{AutoCommit};

    $dbh->begin_work;

    my @resultado = eval { $codigo->($dbh) };

    if ($@) {
        my $error = $@;
        eval { $dbh->rollback };    # si el rollback falla, importa el error original
        die $error;
    }

    $dbh->commit;

    return wantarray ? @resultado : $resultado[0];
}

# ---------------------------------------------------------------------
# Cierra la conexion. Bajo CGI no hace falta llamarla (el proceso
# termina y se cierra sola); esta para los scripts de consola.
# ---------------------------------------------------------------------
sub desconectar {
    if ($DBH) {
        $DBH->disconnect;
        undef $DBH;
    }
    return;
}

1;
