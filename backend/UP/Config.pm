package UP::Config;

# =====================================================================
# Lectura de config/app.conf
#
# No usa modulos de configuracion externos a proposito: el formato es
# clave=valor y el parseo entra en veinte lineas, asi que agregar una
# dependencia solo complicaria la instalacion para quien evalue esto.
# =====================================================================

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;

# Raiz del proyecto, deducida de la ubicacion de este archivo:
#   <raiz>/backend/UP/Config.pm  ->  subir dos niveles
# Se calcula asi, y no con el directorio de trabajo, porque un CGI
# corre con el cwd que le pone Apache, que no es el del proyecto.
my $RAIZ = File::Spec->rel2abs(
    File::Spec->catdir( dirname(__FILE__), File::Spec->updir, File::Spec->updir )
);

my $ARCHIVO = File::Spec->catfile( $RAIZ, 'config', 'app.conf' );

my @REQUERIDAS = qw(db_host db_port db_name db_user db_pass);

my $CACHE;

# ---------------------------------------------------------------------
# Directorio raiz del proyecto.
# ---------------------------------------------------------------------
sub raiz { return $RAIZ }

# ---------------------------------------------------------------------
# Hashref con toda la configuracion. Se lee una sola vez por proceso.
# ---------------------------------------------------------------------
sub todo {
    return $CACHE if $CACHE;

    open my $fh, '<', $ARCHIVO
        or die "No se pudo abrir la configuracion '$ARCHIVO': $!\n"
             . "Copiala desde config/app.conf.example y ajusta los valores.\n";

    my %cfg;
    while ( my $linea = <$fh> ) {
        chomp $linea;
        next if $linea =~ /^\s*#/;      # comentario
        next if $linea =~ /^\s*$/;      # linea vacia

        my ( $clave, $valor ) = $linea =~ /^\s*([\w.]+)\s*=\s*(.*?)\s*$/
            or die "Linea invalida en '$ARCHIVO' (linea $.): $linea\n";

        $cfg{$clave} = $valor;
    }
    close $fh;

    my @faltan = grep { !defined $cfg{$_} || $cfg{$_} eq '' } @REQUERIDAS;
    die "Faltan claves en '$ARCHIVO': @faltan\n" if @faltan;

    $CACHE = \%cfg;
    return $CACHE;
}

# ---------------------------------------------------------------------
# Un valor puntual. Muere si la clave no existe, en vez de devolver
# undef y hacer que el error aparezca tres capas mas arriba.
# ---------------------------------------------------------------------
sub get {
    my ( $class, $clave ) = @_;
    my $cfg = $class->todo;

    die "Clave de configuracion desconocida: '$clave'\n"
        unless exists $cfg->{$clave};

    return $cfg->{$clave};
}

1;
