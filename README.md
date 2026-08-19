# Inscripción de alumnos a carreras

Aplicación web con una parte pública, donde un alumno se inscribe a una carrera, y una parte privada (ABM) protegida con `.htaccess`.

**Stack:** Perl (backend) · HTML + JavaScript (frontend) · PostgreSQL (base de datos) · Apache con `mod_cgi`.

---

## Antes de empezar

**1. Ubicá el proyecto donde quieras**, pero anotá la ruta completa: hace falta en dos lugares de la configuración de Apache.

```bash
git clone https://github.com/FacuIbrra1/Ejercicio-UP.git
```

**2. En Windows, hacé toda la instalación desde PowerShell o CMD, no desde Git Bash.**

No es una preferencia. Git para Windows trae su propio Perl en `/usr/bin/perl` y se adelanta al de Strawberry en el `PATH`. Eso rompe dos cosas en silencio:

| Comando | En PowerShell | En Git Bash |
|---|---|---|
| `cpanm DBD::Pg` | instala en Strawberry ✅ | instala en el Perl de Git ❌ |
| `perl tests/…` | usa Strawberry ✅ | falla con `Can't locate DBI.pm` ❌ |

El caso de `cpanm` es el peor, porque **no da error**: instala el módulo en un Perl que la aplicación nunca usa, y después los CGI fallan sin que se entienda por qué.

---

## 1. Requisitos

| Componente | Versión probada | Para qué |
|---|---|---|
| Perl | 5.42 (Strawberry Perl en Windows) | backend |
| PostgreSQL | 17 | base de datos |
| Apache | 2.4 con `mod_cgi` | servidor web |

Módulos Perl: `DBI`, `DBD::Pg`, y `JSON::PP` + `Encode` + `HTTP::Tiny` (los tres vienen con Perl).

Solo hay que instalar uno:

```bash
cpanm DBD::Pg
```

> **Si `DBD::Pg` no compila en Windows**, es por un choque de compiladores: el instalador oficial de PostgreSQL está hecho con MSVC y su `libpq.a` arrastra símbolos del runtime de Microsoft (`__security_cookie`, `__GSHandlerCheck`) que el linker mingw de Strawberry Perl no resuelve.
>
> La solución es contraintuitiva: **no** definir `POSTGRES_HOME` ni `POSTGRES_LIB`. Sin esas variables, el build usa la `libpq.a` propia de Strawberry, que sí está compilada con mingw. Un `cpanm DBD::Pg` pelado funciona.

---

## 2. Base de datos

Los tres scripts son idempotentes: se pueden volver a correr.

**Paso 1** — rol y base. Necesita superusuario, se ejecuta una sola vez:

```bash
psql -U postgres -f database/00_crear_base.sql
```

Crea el rol `up_app` (contraseña `up_app_dev`) y la base `inscripciones_up`.

**Paso 2** — tablas:

```bash
psql -U up_app -d inscripciones_up -f database/01_schema.sql
```

> Este script hace `DROP TABLE` antes de crear, para poder re-ejecutarse. Sobre una base con datos, los borra.

**Paso 3** — carreras de ejemplo:

```bash
psql -U up_app -d inscripciones_up -f database/02_seed.sql
```

**Encoding:** la base tiene que ser UTF8. `01_schema.sql` lo verifica al arrancar y falla con un mensaje claro si no lo es, porque los nombres de carrera llevan tildes y eñes.

---

## 3. Configuración

```bash
cp config/app.conf.example config/app.conf
```

Ajustar los valores si hiciera falta:

```
db_host = 127.0.0.1
db_port = 5432
db_name = inscripciones_up
db_user = up_app
db_pass = up_app_dev
```

`config/app.conf` **no se versiona** (está en `.gitignore`) porque lleva la contraseña.

---

## 4. Apache

El repositorio trae la configuración lista en **`config/httpd-up.conf.example`**. Copiala a la carpeta `conf/extra/` de Apache con el nombre `httpd-up.conf`:

```bash
copy config\httpd-up.conf.example C:\xampp\apache\conf\extra\httpd-up.conf
```

Editá ese archivo y reemplazá las cuatro rutas por la ubicación real del proyecto (aparecen en los dos `Alias` y en los dos `<Directory>`).

Después agregá esta línea al final de `C:\xampp\apache\conf\httpd.conf`:

```apache
Include "conf/extra/httpd-up.conf"
```

Este es el contenido, por si preferís escribirlo a mano:

```apache
Alias /up/admin "RUTA/DEL/PROYECTO/frontend/admin"
Alias /up       "RUTA/DEL/PROYECTO/frontend/publico"

AddCharset UTF-8 .html .css .js

<LocationMatch "^/up(/|$)">
    <IfModule mod_headers.c>
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Frame-Options "DENY"
        Header always set Referrer-Policy "same-origin"
        Header always set Content-Security-Policy "default-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
    </IfModule>
</LocationMatch>

<Directory "RUTA/DEL/PROYECTO/frontend/publico">
    Options +ExecCGI -Indexes
    DirectoryIndex index.html
    AllowOverride None
    Require all granted
</Directory>

<Directory "RUTA/DEL/PROYECTO/frontend/admin">
    Options +ExecCGI -Indexes
    DirectoryIndex index.html
    AllowOverride AuthConfig
    Require all granted
</Directory>
```

Verificar la sintaxis de la configuración:

```bash
httpd -t
```

> **En Windows con XAMPP, `httpd` no está en el `PATH`.** Hay que llamarlo por su ruta completa:
>
> ```bash
> "/c/xampp/apache/bin/httpd.exe" -t
> ```
>
> (desde Git Bash; en PowerShell sería `& "C:\xampp\apache\bin\httpd.exe" -t`)

Esperado: `Syntax OK`.

**Para arrancar Apache, usá el XAMPP Control Panel** y el botón *Start* de la fila Apache. No conviene levantarlo desde una consola: el proceso queda colgado de esa terminal y se cae al cerrarla. Además, el Control Panel hereda el `PATH` completo del sistema, que es lo que necesita `DBD::Pg` para encontrar `libpq__.dll` (ver el punto 2 más abajo).

Comprobar que quedó levantado:

```bash
curl -i http://localhost/up/api/carreras.cgi
```

Esperado: `HTTP/1.1 200 OK`.

**Dos detalles importantes:**

1. **Solo se publican `frontend/publico/` y `frontend/admin/`.** `backend/`, `config/`, `database/` y `tests/` quedan fuera del árbol servido, así que no hay ninguna URL que llegue a ellos. Es deliberado: publicar la raíz y después bloquear lo sensible con reglas deja lugar a olvidarse una; así no hay nada que olvidar. En particular, `config/app.conf` y `config/.htpasswd` son inaccesibles por construcción.

2. **En Windows, Apache tiene que arrancar con `C:\Strawberry\c\bin` en el `PATH`.** El `Pg.xs.dll` de `DBD::Pg` depende en tiempo de ejecución de `libpq__.dll`, que vive ahí. Si Apache se levanta desde una consola con un `PATH` viejo, los CGI fallan con `load_file: no se puede encontrar el módulo especificado` — un error que despista, porque los mismos scripts andan perfecto por consola. Arrancándolo desde el XAMPP Control Panel no pasa.

**Shebang:** los `.cgi` apuntan a `#!C:/Strawberry/perl/bin/perl.exe`. En Linux hay que cambiarlo a `#!/usr/bin/perl` (o donde esté Perl).

---

## 5. Acceso a la parte privada

Lo más rápido es usar el archivo de ejemplo, que ya trae el usuario **`admin`** con la contraseña **`up2026`**:

```bash
copy config\.htpasswd.example config\.htpasswd
```

Para generar uno propio con otra contraseña:

```bash
"C:\xampp\apache\bin\htpasswd.exe" -B config\.htpasswd admin
```

> **`htpasswd` no está en el `PATH`**, igual que `httpd`: XAMPP no agrega su carpeta `bin`. Hay que llamarlo por la ruta completa.

Después hay que poner la **ruta absoluta** a ese archivo en `frontend/admin/.htaccess`:

```apache
AuthUserFile "RUTA/DEL/PROYECTO/config/.htpasswd"
```

El `-B` usa bcrypt en lugar del MD5 que `htpasswd` trae por defecto: es lento a propósito, así que si alguien consiguiera el archivo, romperlo por fuerza bruta le costaría mucho más.

---

## 6. Uso

| Zona | URL | Acceso |
|---|---|---|
| Formulario de inscripción | `http://localhost/up/` | público |
| Administración (ABM) | `http://localhost/up/admin/` | `admin` / `up2026` |

### Verificación rápida

Tres comandos que prueban la cadena entera —Apache, CGI, Perl, PostgreSQL— sin abrir el navegador:

```bash
curl -i http://localhost/up/api/carreras.cgi
```

Esperado: `200 OK` y un JSON con 12 carreras. Si falla acá, el problema está en Apache o en `DBD::Pg`.

```bash
curl -i http://localhost/up/admin/api/alumnos.cgi
```

Esperado: `401 Unauthorized`. Confirma que la parte privada está protegida.

```bash
curl -i -u admin:up2026 http://localhost/up/admin/api/alumnos.cgi
```

Esperado: `200 OK`. Confirma que las credenciales funcionan.

Si los tres dan lo esperado, la instalación está completa.

#### Si algo falla

| Síntoma | Causa habitual |
|---|---|
| `Connection refused` | Apache no está corriendo |
| `500 Internal Server Error` | Ver `C:\xampp\apache\logs\error.log`. Suele ser `DBD::Pg` o `config/app.conf` |
| `load_file: no se puede encontrar el módulo` | Apache arrancó sin `C:\Strawberry\c\bin` en el `PATH`; levantalo desde el XAMPP Control Panel |
| `404` en `/up/` | El `Alias` de `httpd-up.conf` apunta a una ruta que no existe |
| `500` al entrar a `/up/admin/` | La ruta de `AuthUserFile` en `frontend/admin/.htaccess` está mal |

---

## 7. Estructura

Las tres capas están separadas físicamente, con una regla que no se rompe: **un `.cgi` nunca escribe SQL, y un repositorio nunca sabe qué es un código HTTP.**

```
frontend/                     lo único que Apache publica
├─ publico/
│  ├─ index.html, css/, js/, favicon.svg
│  └─ api/                    carreras.cgi · inscripciones.cgi
└─ admin/
   ├─ index.html, css/, js/
   ├─ api/                    alumnos.cgi · inscripciones.cgi · carreras.cgi
   └─ .htaccess               protege la pantalla Y la api/

backend/UP/                   nada de esto tiene URL
├─ Config.pm  DB.pm  Error.pm
├─ Repo/                      ACCESO A DATOS · DBI y SQL, nada más
├─ Service/                   NEGOCIO · validación y reglas
└─ Web/Api.pm                 HTTP · la única capa que conoce el protocolo

database/                     scripts SQL
config/                       configuración y credenciales
tests/                        las cuatro suites
```

**Por qué los `.cgi` están bajo `frontend/`** aunque sean código Perl: son el punto de entrada HTTP, y Apache solo los ejecuta si están dentro del directorio que publica. Manteniéndolos junto a la pantalla que sirven, un solo `.htaccess` en `frontend/admin/` protege la pantalla **y** los endpoints. Sacarlos a `backend/` obligaría a usar `ScriptAlias` y a duplicar el `.htaccess` en dos directorios, que es más superficie donde equivocarse.

Son controladores de veinte líneas: traducen parámetros y delegan. Toda la mecánica de HTTP vive en `backend/UP/Web/Api.pm`.

| Archivo | Responsabilidad |
|---|---|
| `backend/UP/Config.pm` | lee `config/app.conf`; ubica la raíz desde `__FILE__`, no desde el directorio de trabajo, porque Apache no garantiza cuál es el `cwd` de un CGI |
| `backend/UP/DB.pm` | única pieza que sabe que hay DBI y PostgreSQL detrás; incluye el helper de transacción |
| `backend/UP/Repo/*.pm` | SQL, siempre con placeholders |
| `backend/UP/Service/*.pm` | validación, reglas de negocio, límites de transacción |
| `backend/UP/Error.pm` | error de negocio tipado; **no** conoce HTTP |
| `backend/UP/Web/Api.pm` | única capa que sabe que existe el protocolo: traduce código de error a status |

---

## 8. La API

Respuesta uniforme:

```json
{ "ok": true,  "data": ... }
{ "ok": false, "error": { "codigo": "ALUMNO_YA_INSCRIPTO", "mensaje": "..." } }
```

| Método | Endpoint | Acceso | Éxito | Errores |
|---|---|---|---|---|
| GET | `/up/api/carreras.cgi` | público | 200 | |
| POST | `/up/api/inscripciones.cgi` | público | 201 | 400 · 409 |
| GET | `/up/frontend/admin/api/carreras.cgi` | privado | 200 | |
| GET | `/up/frontend/admin/api/alumnos.cgi` | privado | 200 | |
| GET | `/up/frontend/admin/api/alumnos.cgi?id=N` | privado | 200 | 404 |
| POST | `/up/frontend/admin/api/alumnos.cgi` | privado | 201 | 400 · 409 |
| PUT | `/up/frontend/admin/api/alumnos.cgi?id=N` | privado | 200 | 400 · 404 · 409 |
| DELETE | `/up/frontend/admin/api/alumnos.cgi?id=N` | privado | 200 | 404 |
| POST | `/up/frontend/admin/api/inscripciones.cgi` | privado | 201 | 400 · 404 · 409 |
| DELETE | `/up/frontend/admin/api/inscripciones.cgi?id=N` | privado | 200 | 404 |

Códigos de error: `VALIDACION`, `EMAIL_DUPLICADO`, `ALUMNO_YA_INSCRIPTO`, `CARRERA_INVALIDA`, `NO_ENCONTRADO`, `METODO_NO_PERMITIDO`, `ERROR_INTERNO`.

---

## 9. Decisiones de diseño

### El modelo es N:M

La consigna dice *"si un alumno ya está inscripto, debe mostrarse un error"*, y eso admite dos lecturas: que el alumno ya exista, o que ya esté inscripto **a esa carrera**. Se eligió la segunda.

```
alumno ──< inscripcion >── carrera
```

- `alumno.email` es único: una persona existe una sola vez.
- `inscripcion (alumno_id, carrera_id)` es único: **esa es la regla que dispara el error**.

Cada inscripción asigna exactamente una carrera, que es lo que pide la consigna, pero el alumno no queda limitado a una sola de por vida. Si alguien ya registrado elige otra carrera, se reutiliza su ficha.

### El error de duplicado tiene dos formas

| Situación | Código | HTTP |
|---|---|---|
| El alumno ya está inscripto a esa carrera | `ALUMNO_YA_INSCRIPTO` | 409 |
| Se intenta crear o editar un alumno con el email de otro | `EMAIL_DUPLICADO` | 409 |

### La garantía contra duplicados está en la base, no en Perl

Hay un `SELECT` previo, pero solo para dar un mensaje amable. Lo que realmente impide el duplicado son las constraints `ux_alumno_email` y `ux_inscripcion_alumno_carrera`: entre el `SELECT` y el `INSERT` puede colarse otro proceso, y la base es el único punto donde esa carrera no existe.

Para traducir el error de PostgreSQL al código de negocio no se parsea el mensaje —cambia entre versiones e idiomas— sino que se mira **qué sentencia falló**: un `23505` en el `INSERT INTO alumno` solo puede ser email repetido; uno en `INSERT INTO inscripcion`, carrera repetida.

### El alta pública no pisa los datos de un alumno existente

El formulario público no pide ninguna prueba de que sos el dueño de ese email. Permitir la sobreescritura dejaría que cualquiera que conozca tu dirección te cambie el teléfono. Los datos se corrigen desde el ABM.

### Cuatro capas contra XSS

1. Placeholders DBI: el dato entra a la base como dato, nunca como SQL.
2. Validación del servidor.
3. `textContent` en todo el frontend: nada se inserta con `innerHTML`.
4. `Content-Security-Policy: default-src 'self'`: aunque un script lograra entrar en el HTML, el navegador no lo ejecutaría.

### El `.htaccess` protege el directorio, no el HTML

Está en `admin/`, así que Apache lo aplica a todo lo que cuelga de ahí, **incluido `frontend/admin/api/`**. Si cubriera solo `index.html`, cualquiera podría pegarle directo a `frontend/admin/api/alumnos.cgi` y borrar alumnos sin ver nunca una pantalla de login.

---

## 10. Limitaciones conocidas

- **Basic Auth manda usuario y contraseña en base64 en cada pedido, y base64 no es cifrado.** Sobre HTTP plano, cualquiera que vea el tráfico las lee. Es lo que pide la consigna y alcanza en local, pero en producción esto exige HTTPS obligatorio.
- **Las contraseñas de este repositorio son de demostración** (`up_app_dev`, `up2026`) y están documentadas a propósito para que la aplicación se pueda levantar. En cualquier uso real hay que cambiarlas.
- **No hay ABM de carreras**: la consigna no lo pide. Las carreras se cargan con `database/02_seed.sql`. El campo `carrera.activa` ya existe para poder dar una de baja sin romper las inscripciones históricas.
- **El listado del ABM no está paginado.** Con el volumen del ejercicio no hace falta; con decenas de miles de alumnos habría que agregarla.

---

## 11. Pruebas

Cuatro suites, 111 chequeos, que corren contra la base real y limpian lo que crean.

**Se pueden correr en cualquier momento, con o sin datos cargados.** El último chequeo de cada suite no exige que las tablas estén vacías, sino que compara el estado contra una foto tomada al empezar: lo que se verifica es que la prueba no haya dejado nada atrás, no que la base esté limpia.

> **En Git Bash no uses `perl` a secas.** Git para Windows trae su propio Perl en `/usr/bin/perl` y se adelanta al de Strawberry en el `PATH`. Ese Perl no tiene `DBI`, así que `prueba_capa_datos` y `prueba_negocio` fallan con `Can't locate DBI.pm in @INC`.
>
> El síntoma despista, porque **las otras dos suites sí pasan**: solo usan `HTTP::Tiny`, que viene con cualquier Perl. Dos en verde y dos en rojo parece un bug de la aplicación, y es solo el intérprete equivocado.
>
> Desde Git Bash hay que llamar al de Strawberry por su ruta completa:
>
> ```bash
> /c/Strawberry/perl/bin/perl.exe tests/prueba_capa_datos.pl
> ```
>
> Desde **PowerShell o CMD no pasa**: ahí `perl` resuelve directo a Strawberry. Los comandos de abajo están escritos para esas dos consolas.

```bash
perl tests/prueba_capa_datos.pl
```

```bash
perl tests/prueba_negocio.pl
```

```bash
perl tests/prueba_api.pl http://localhost/up admin:up2026
```

```bash
perl tests/prueba_seguridad.pl http://localhost/up admin:up2026
```

| Suite | Chequeos | Qué cubre |
|---|---|---|
| `prueba_capa_datos.pl` | 20 | repositorios, transacciones, `CASCADE`, UTF-8 |
| `prueba_negocio.pl` | 25 | validaciones y los cinco códigos de error |
| `prueba_api.pl` | 31 | los 10 endpoints por HTTP real, con sus status |
| `prueba_seguridad.pl` | 35 | control de acceso, archivos internos, cabeceras |

Las dos últimas no importan ningún módulo del proyecto: hablan con la aplicación por la red, igual que un navegador, así que también validan la configuración de Apache.
