/* =====================================================================
   ABM de alumnos.

   No hay lógica de negocio acá: cada acción es una llamada a la API,
   y las reglas (duplicados, validación) las resuelve el servidor.

   Todo dato que llega del servidor entra por textContent. En un ABM
   importa más todavía: los nombres y emails los escribió otra
   persona, y son la vía por donde entraría un XSS almacenado.
   ===================================================================== */

(function () {
    'use strict';

    var API_ALUMNOS = 'api/alumnos.cgi';
    var API_INSCRIPCIONES = 'api/inscripciones.cgi';
    var API_CARRERAS = 'api/carreras.cgi';

    var CAMPOS = ['nombre', 'email', 'telefono', 'nacionalidad', 'carrera_id'];

    var MENSAJE_GENERICO = 'Ocurrió un error. Probá de nuevo en unos minutos.';

    var estado = {
        alumnos: [],
        carreras: [],
        editando: null,      // id del alumno en edición, o null si es un alta
        gestionando: null,   // alumno cuyas carreras se están gestionando
        dandoBaja: null
    };

    var $ = function (id) { return document.getElementById(id); };

    var cuerpo = $('cuerpo');
    var buscar = $('buscar');
    var alerta = $('alerta');
    var aviso = $('aviso');
    var resumen = $('resumen');
    var vacio = $('vacio');

    var dlgAlumno = $('dialogo-alumno');
    var dlgCarreras = $('dialogo-carreras');
    var dlgBaja = $('dialogo-baja');

    /* --- Llamadas a la API ------------------------------------------ */

    function api(metodo, ruta, datos) {
        var opciones = {
            method: metodo,
            headers: { Accept: 'application/json' }
        };

        if (datos !== undefined) {
            opciones.headers['Content-Type'] = 'application/json';
            opciones.body = JSON.stringify(datos);
        }

        return fetch(ruta, opciones).then(function (respuesta) {
            // Si el servidor devolviera HTML (una página de error de
            // Apache, o el pedido de login del .htaccess), .json()
            // falla. Se atrapa para mostrar algo entendible.
            return respuesta.json().then(
                function (c) { return { ok: respuesta.ok, estado: respuesta.status, cuerpo: c }; },
                function () { return { ok: false, estado: respuesta.status, cuerpo: null }; }
            );
        });
    }

    /* --- Avisos ------------------------------------------------------ */

    function comportamientoScroll() {
        var prefiereQuieto = window.matchMedia
            && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        return prefiereQuieto ? 'auto' : 'smooth';
    }

    function mostrarAlerta(texto) {
        alerta.textContent = texto;
        alerta.hidden = false;
        window.scrollTo({ top: 0, behavior: comportamientoScroll() });
    }

    function mostrarAviso(texto) {
        aviso.textContent = texto;
        aviso.hidden = false;
        clearTimeout(mostrarAviso.reloj);
        mostrarAviso.reloj = setTimeout(function () { aviso.hidden = true; }, 4000);
    }

    function limpiarAvisos() {
        alerta.hidden = true;
        aviso.hidden = true;
    }

    /* --- Errores dentro de un diálogo -------------------------------- */

    function limpiarErroresFormulario() {
        CAMPOS.forEach(function (campo) {
            var entrada = $('f-' + campo);
            var destino = $('error-f-' + campo);
            if (entrada) {
                entrada.classList.remove('invalido');
                entrada.removeAttribute('aria-invalid');
            }
            if (destino) { destino.textContent = ''; }
        });
        $('error-alumno').textContent = '';
    }

    // Traduce el error del servidor a lo que se muestra en pantalla.
    function pintarError(resultado, destinoGeneral) {
        var error = (resultado.cuerpo && resultado.cuerpo.error) || {};

        if (error.codigo === 'VALIDACION' && error.campos) {
            var primero = null;
            Object.keys(error.campos).forEach(function (campo) {
                var entrada = $('f-' + campo);
                var destino = $('error-f-' + campo);
                if (entrada) {
                    entrada.classList.add('invalido');
                    entrada.setAttribute('aria-invalid', 'true');
                    if (!primero) { primero = entrada; }
                }
                if (destino) { destino.textContent = error.campos[campo]; }
            });
            if (primero) { primero.focus(); }
            if (destinoGeneral) { destinoGeneral.textContent = 'Revisá los datos marcados.'; }
            return;
        }

        var texto = error.mensaje || MENSAJE_GENERICO;

        // EMAIL_DUPLICADO apunta a un campo concreto, así que el
        // mensaje va ahí y no se repite abajo. El mismo texto dos
        // veces hace pensar que son dos problemas distintos.
        if (error.codigo === 'EMAIL_DUPLICADO' && $('f-email')) {
            var campoEmail = $('f-email');
            campoEmail.classList.add('invalido');
            campoEmail.setAttribute('aria-invalid', 'true');
            $('error-f-email').textContent = texto;
            campoEmail.focus();

            if (destinoGeneral) { destinoGeneral.textContent = ''; }
            return;
        }

        // El resto de los errores no son de ningún campo en
        // particular, así que van al lugar general.
        if (destinoGeneral) { destinoGeneral.textContent = texto; }
    }

    /* --- Carga y pintado --------------------------------------------- */

    function cargar() {
        return Promise.all([
            api('GET', API_CARRERAS),
            api('GET', API_ALUMNOS)
        ]).then(function (respuestas) {
            var carreras = respuestas[0];
            var alumnos = respuestas[1];

            if (!carreras.ok || !alumnos.ok) {
                fallaDeCarga('No pudimos cargar los datos. Recargá la página.');
                return;
            }

            estado.carreras = carreras.cuerpo.data || [];
            estado.alumnos = alumnos.cuerpo.data || [];
            pintar();
        }).catch(function () {
            fallaDeCarga('No pudimos conectarnos con el servidor.');
        });
    }

    // Si la carga falla, el cartel no puede quedarse en "Cargando…"
    // para siempre: hay que decir que no se pudo.
    function fallaDeCarga(texto) {
        mostrarAlerta(texto);
        vacio.textContent = 'No se pudieron cargar los alumnos.';
        vacio.hidden = false;
        document.querySelector('.tabla-envoltorio').hidden = true;
    }

    function coincide(alumno, filtro) {
        if (!filtro) { return true; }

        var texto = [
            alumno.nombre,
            alumno.email,
            alumno.telefono,
            alumno.nacionalidad
        ].concat(
            (alumno.carreras || []).map(function (c) { return c.carrera_nombre; })
        ).join(' ').toLowerCase();

        return texto.indexOf(filtro) !== -1;
    }

    function celda(texto, etiqueta, clase) {
        var td = document.createElement('td');
        td.dataset.etiqueta = etiqueta;

        if (texto === null || texto === undefined || texto === '') {
            var vacia = document.createElement('span');
            vacia.className = 'sin-dato';
            vacia.textContent = '—';
            td.appendChild(vacia);
        } else {
            td.textContent = texto;
        }

        if (clase) { td.classList.add(clase); }
        return td;
    }

    function celdaCarreras(alumno) {
        var td = document.createElement('td');
        td.dataset.etiqueta = 'Carreras';

        var lista = alumno.carreras || [];

        if (lista.length === 0) {
            var ninguna = document.createElement('span');
            ninguna.className = 'sin-dato';
            ninguna.textContent = 'sin carreras';
            td.appendChild(ninguna);
            return td;
        }

        var envoltorio = document.createElement('div');
        envoltorio.className = 'etiquetas';

        lista.forEach(function (carrera) {
            var etiqueta = document.createElement('span');
            etiqueta.className = 'etiqueta';
            etiqueta.textContent = carrera.carrera_nombre;
            envoltorio.appendChild(etiqueta);
        });

        td.appendChild(envoltorio);
        return td;
    }

    function celdaAcciones(alumno) {
        var td = document.createElement('td');
        td.dataset.etiqueta = 'Acciones';

        var envoltorio = document.createElement('div');
        envoltorio.className = 'acciones';

        [
            { accion: 'carreras', texto: 'Carreras', clase: '' },
            { accion: 'editar', texto: 'Editar', clase: '' },
            { accion: 'baja', texto: 'Baja', clase: 'peligro' }
        ].forEach(function (spec) {
            var boton = document.createElement('button');
            boton.type = 'button';
            boton.className = 'boton-chico' + (spec.clase ? ' ' + spec.clase : '');
            boton.textContent = spec.texto;
            boton.dataset.accion = spec.accion;
            boton.dataset.id = alumno.id;
            envoltorio.appendChild(boton);
        });

        td.appendChild(envoltorio);
        return td;
    }

    function pintar() {
        var filtro = buscar.value.trim().toLowerCase();

        var visibles = estado.alumnos.filter(function (a) {
            return coincide(a, filtro);
        });

        cuerpo.textContent = '';

        visibles.forEach(function (alumno) {
            var tr = document.createElement('tr');
            tr.appendChild(celda(alumno.nombre, 'Nombre', 'nombre-alumno'));
            tr.appendChild(celda(alumno.email, 'Email'));
            tr.appendChild(celda(alumno.telefono, 'Teléfono'));
            tr.appendChild(celda(alumno.nacionalidad, 'Nacionalidad'));
            tr.appendChild(celdaCarreras(alumno));
            tr.appendChild(celdaAcciones(alumno));
            cuerpo.appendChild(tr);
        });

        var total = estado.alumnos.length;

        if (total === 0) {
            vacio.textContent = 'Todavía no hay alumnos registrados.';
            vacio.hidden = false;
        } else if (visibles.length === 0) {
            vacio.textContent = 'Ningún alumno coincide con la búsqueda.';
            vacio.hidden = false;
        } else {
            vacio.hidden = true;
        }

        document.querySelector('.tabla-envoltorio').hidden = visibles.length === 0;

        resumen.textContent = filtro
            ? visibles.length + ' de ' + total + ' alumnos'
            : total + (total === 1 ? ' alumno' : ' alumnos');
    }

    /* --- Combo de carreras -------------------------------------------- */

    function llenarSelect(select, carreras, textoVacio) {
        select.textContent = '';

        var vacia = document.createElement('option');
        vacia.value = '';
        vacia.textContent = textoVacio;
        select.appendChild(vacia);

        carreras.forEach(function (carrera) {
            var opcion = document.createElement('option');
            opcion.value = carrera.id;
            opcion.textContent = carrera.nombre;
            select.appendChild(opcion);
        });
    }

    /* --- Alta y modificación ------------------------------------------ */

    function abrirAlta() {
        estado.editando = null;
        limpiarErroresFormulario();

        $('titulo-alumno').textContent = 'Nuevo alumno';
        $('f-nombre').value = '';
        $('f-email').value = '';
        $('f-telefono').value = '';
        $('f-nacionalidad').value = '';

        // Solo las activas: no tiene sentido inscribir a alguien en
        // una carrera que ya no se ofrece.
        llenarSelect(
            $('f-carrera_id'),
            estado.carreras.filter(function (c) { return c.activa; }),
            'Elegí una carrera…'
        );
        $('campo-carrera').hidden = false;

        dlgAlumno.showModal();
        $('f-nombre').focus();
    }

    function abrirEdicion(id) {
        var alumno = estado.alumnos.find(function (a) { return a.id === id; });
        if (!alumno) { return; }

        estado.editando = id;
        limpiarErroresFormulario();

        $('titulo-alumno').textContent = 'Editar alumno';
        $('f-nombre').value = alumno.nombre || '';
        $('f-email').value = alumno.email || '';
        $('f-telefono').value = alumno.telefono || '';
        $('f-nacionalidad').value = alumno.nacionalidad || '';

        // En la edición no se toca la carrera: eso se hace desde el
        // diálogo de carreras, que permite tener varias.
        $('campo-carrera').hidden = true;

        dlgAlumno.showModal();
        $('f-nombre').focus();
    }

    function guardarAlumno(evento) {
        evento.preventDefault();
        limpiarErroresFormulario();

        var datos = {
            nombre: $('f-nombre').value.trim(),
            email: $('f-email').value.trim(),
            telefono: $('f-telefono').value.trim(),
            nacionalidad: $('f-nacionalidad').value.trim()
        };

        var esAlta = estado.editando === null;
        if (esAlta) {
            datos.carrera_id = $('f-carrera_id').value;
        }

        var boton = $('guardar');
        boton.disabled = true;

        var peticion = esAlta
            ? api('POST', API_ALUMNOS, datos)
            : api('PUT', API_ALUMNOS + '?id=' + encodeURIComponent(estado.editando), datos);

        peticion.then(function (resultado) {
            if (resultado.ok && resultado.cuerpo && resultado.cuerpo.ok) {
                dlgAlumno.close();
                mostrarAviso(esAlta ? 'Alumno dado de alta.' : 'Cambios guardados.');
                return cargar();
            }
            pintarError(resultado, $('error-alumno'));
        }).catch(function () {
            $('error-alumno').textContent = 'No pudimos conectarnos con el servidor.';
        }).then(function () {
            boton.disabled = false;
        });
    }

    /* --- Carreras de un alumno ----------------------------------------- */

    function abrirCarreras(id) {
        var alumno = estado.alumnos.find(function (a) { return a.id === id; });
        if (!alumno) { return; }

        estado.gestionando = alumno;
        $('error-carreras').textContent = '';
        $('carreras-alumno').textContent = alumno.nombre;

        pintarCarrerasDelAlumno();

        dlgCarreras.showModal();
    }

    function pintarCarrerasDelAlumno() {
        var alumno = estado.gestionando;
        var lista = $('lista-carreras');
        lista.textContent = '';

        var suyas = alumno.carreras || [];

        if (suyas.length === 0) {
            var li = document.createElement('li');
            li.className = 'ninguna';
            li.textContent = 'No está inscripto a ninguna carrera.';
            lista.appendChild(li);
        } else {
            suyas.forEach(function (carrera) {
                var li = document.createElement('li');

                var nombre = document.createElement('span');
                nombre.textContent = carrera.carrera_nombre;
                li.appendChild(nombre);

                var quitar = document.createElement('button');
                quitar.type = 'button';
                quitar.className = 'boton-chico peligro';
                quitar.textContent = 'Quitar';
                quitar.dataset.inscripcion = carrera.inscripcion_id;
                li.appendChild(quitar);

                lista.appendChild(li);
            });
        }

        // El combo ofrece solo lo que le falta: proponer una carrera
        // que ya tiene sería ofrecer un error seguro.
        var yaTiene = suyas.map(function (c) { return c.carrera_id; });
        var disponibles = estado.carreras.filter(function (c) {
            return c.activa && yaTiene.indexOf(c.id) === -1;
        });

        llenarSelect(
            $('f-nueva-carrera'),
            disponibles,
            disponibles.length ? 'Elegí una carrera…' : 'No quedan carreras para agregar'
        );
        $('agregar-carrera').disabled = disponibles.length === 0;
    }

    function refrescarGestionando() {
        return cargar().then(function () {
            if (!estado.gestionando) { return; }
            var actualizado = estado.alumnos.find(function (a) {
                return a.id === estado.gestionando.id;
            });
            if (actualizado) {
                estado.gestionando = actualizado;
                pintarCarrerasDelAlumno();
            }
        });
    }

    function agregarCarrera() {
        var carreraId = $('f-nueva-carrera').value;
        $('error-carreras').textContent = '';

        if (!carreraId) {
            $('error-carreras').textContent = 'Elegí una carrera.';
            return;
        }

        var boton = $('agregar-carrera');
        boton.disabled = true;

        api('POST', API_INSCRIPCIONES, {
            alumno_id: estado.gestionando.id,
            carrera_id: carreraId
        }).then(function (resultado) {
            if (resultado.ok && resultado.cuerpo && resultado.cuerpo.ok) {
                mostrarAviso('Carrera asignada.');
                return refrescarGestionando();
            }
            var error = (resultado.cuerpo && resultado.cuerpo.error) || {};
            $('error-carreras').textContent = error.mensaje || MENSAJE_GENERICO;
        }).catch(function () {
            $('error-carreras').textContent = 'No pudimos conectarnos con el servidor.';
        }).then(function () {
            boton.disabled = false;
        });
    }

    function quitarCarrera(inscripcionId) {
        $('error-carreras').textContent = '';

        api('DELETE', API_INSCRIPCIONES + '?id=' + encodeURIComponent(inscripcionId))
            .then(function (resultado) {
                if (resultado.ok && resultado.cuerpo && resultado.cuerpo.ok) {
                    mostrarAviso('Carrera quitada.');
                    return refrescarGestionando();
                }
                var error = (resultado.cuerpo && resultado.cuerpo.error) || {};
                $('error-carreras').textContent = error.mensaje || MENSAJE_GENERICO;
            })
            .catch(function () {
                $('error-carreras').textContent = 'No pudimos conectarnos con el servidor.';
            });
    }

    /* --- Baja ----------------------------------------------------------- */

    function abrirBaja(id) {
        var alumno = estado.alumnos.find(function (a) { return a.id === id; });
        if (!alumno) { return; }

        estado.dandoBaja = alumno;
        $('error-baja').textContent = '';
        $('texto-baja').textContent =
            '¿Confirmás dar de baja a ' + alumno.nombre + ' (' + alumno.email + ')?';

        dlgBaja.showModal();
    }

    function confirmarBaja() {
        var boton = $('confirmar-baja');
        boton.disabled = true;

        api('DELETE', API_ALUMNOS + '?id=' + encodeURIComponent(estado.dandoBaja.id))
            .then(function (resultado) {
                if (resultado.ok && resultado.cuerpo && resultado.cuerpo.ok) {
                    dlgBaja.close();
                    mostrarAviso('Alumno dado de baja.');
                    return cargar();
                }
                var error = (resultado.cuerpo && resultado.cuerpo.error) || {};
                $('error-baja').textContent = error.mensaje || MENSAJE_GENERICO;
            })
            .catch(function () {
                $('error-baja').textContent = 'No pudimos conectarnos con el servidor.';
            })
            .then(function () {
                boton.disabled = false;
            });
    }

    /* --- Cableado --------------------------------------------------------- */

    // Los botones de cada fila se crean y se destruyen en cada
    // pintado, así que el listener va en el tbody y no en cada botón.
    cuerpo.addEventListener('click', function (evento) {
        var boton = evento.target.closest('button[data-accion]');
        if (!boton) { return; }

        var id = Number(boton.dataset.id);
        limpiarAvisos();

        if (boton.dataset.accion === 'editar') { abrirEdicion(id); }
        if (boton.dataset.accion === 'carreras') { abrirCarreras(id); }
        if (boton.dataset.accion === 'baja') { abrirBaja(id); }
    });

    $('lista-carreras').addEventListener('click', function (evento) {
        var boton = evento.target.closest('button[data-inscripcion]');
        if (boton) { quitarCarrera(boton.dataset.inscripcion); }
    });

    document.querySelectorAll('[data-cerrar]').forEach(function (boton) {
        boton.addEventListener('click', function () {
            boton.closest('dialog').close();
        });
    });

    $('nuevo').addEventListener('click', function () {
        limpiarAvisos();
        abrirAlta();
    });

    $('form-alumno').addEventListener('submit', guardarAlumno);
    $('agregar-carrera').addEventListener('click', agregarCarrera);
    $('confirmar-baja').addEventListener('click', confirmarBaja);

    buscar.addEventListener('input', pintar);

    cargar();
})();
