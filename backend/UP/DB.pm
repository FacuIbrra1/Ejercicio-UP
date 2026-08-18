package UP::DB;

# =====================================================================
# Conexion a PostgreSQL.
#
# Es el unico lugar del proyecto que sabe que la base es PostgreSQL y
# que se usa DBI. Los repositorios reciben el handle ya armado.
# =====================================================================

use strict;
use warnings;

use DBI;
use UP::Config;

my $DBH;

# ---------------------------------------------------------------------
# Handle de conexion, reutilizado dentro del mismo proceso.
#
# Bajo CGI cada pedido es un proceso nuevo, asi que se conecta una vez
# por pedido. Guardarlo evita reconectar si el service llama a varios
# repositorios.
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
            # Los errores se lanzan como excepciones y se atrapan con
            # eval en la capa de negocio, en vez de chequear el retorno
            # de cada llamada.
            RaiseError => 1,
            PrintError => 0,

            # Que no escriba en STDERR por su cuenta: bajo CGI eso va a
            # parar al error_log de Apache.
            PrintWarn => 0,

            AutoCommit => 1,

            # Los textos van y vienen como UTF-8, para que las tildes
            # no se rompan.
            pg_enable_utf8 => 1,
        }
    );

    # En Windows el client_encoding puede arrancar en WIN1252 segun el
    # locale, y ahi los acentos se corrompen sin avisar.
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
# Si $codigo muere, hace rollback y vuelve a lanzar el error original
# para que la capa de negocio lo pueda clasificar.
#
# Si ya hay una transaccion abierta se suma a ella: PostgreSQL no tiene
# transacciones anidadas, y abrir una segunda romperia el rollback.
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
