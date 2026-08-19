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

    const API_ALUMNOS = 'api/alumnos.cgi';
    const API_INSCRIPCIONES = 'api/inscripciones.cgi';
    const API_CARRERAS = 'api/carreras.cgi';

    const CAMPOS = ['nombre', 'email', 'telefono', 'nacionalidad', 'carrera_id'];

    const MENSAJE_GENERICO = 'Ocurrió un error. Probá de nuevo en unos minutos.';

    const estado = {
        alumnos: [],
        carreras: [],
        editando: null,      // id del alumno en edición, o null si es un alta
        gestionando: null,   // alumno cuyas carreras se están gestionando
        dandoBaja: null
    };

    const $ = function (id) { return document.getElementById(id); };

    const cuerpo = $('cuerpo');
    const buscar = $('buscar');
    const alerta = $('alerta');
    const aviso = $('aviso');
    const resumen = $('resumen');
    const vacio = $('vacio');

    const dlgAlumno = $('dialogo-alumno');
    const dlgCarreras = $('dialogo-carreras');
    const dlgBaja = $('dialogo-baja');

    /* --- Llamadas a la API ------------------------------------------ */

    async function api(metodo, ruta, datos) {
        const opciones = {
            method: metodo,
            headers: { Accept: 'application/json' }
        };

        if (datos !== undefined) {
            opciones.headers['Content-Type'] = 'application/json';
            opciones.body = JSON.stringify(datos);
        }

        const respuesta = await fetch(ruta, opciones);

        // Si el servidor devolviera HTML (una página de error de
        // Apache, o el pedido de login del .htaccess), .json() falla.
        // Se atrapa para mostrar algo entendible.
        //
        // "leido" distingue "no se pudo parsear" de "parseó y dio
        // null". Sin esa marca habría que usar el cuerpo para
        // deducirlo, y un cuerpo nulo válido se confundiría con un
        // error de parseo.
        let cuerpo = null;
        let leido = false;

        try {
            cuerpo = await respuesta.json();
            leido = true;
        } catch (e) {
            leido = false;
        }

        return {
            ok: leido && respuesta.ok,
            estado: respuesta.status,
            cuerpo: leido ? cuerpo : null
        };
    }

    /* --- Avisos ------------------------------------------------------ */

    function comportamientoScroll() {
        const prefiereQuieto = window.matchMedia
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
            const entrada = $('f-' + campo);
            const destino = $('error-f-' + campo);
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
        const error = (resultado.cuerpo && resultado.cuerpo.error) || {};

        if (error.codigo === 'VALIDACION' && error.campos) {
            // El único que se reasigna: guarda el primer campo con
            // error para llevarle el foco al terminar el recorrido.
            let primero = null;
            Object.keys(error.campos).forEach(function (campo) {
                const entrada = $('f-' + campo);
                const destino = $('error-f-' + campo);
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

        const texto = error.mensaje || MENSAJE_GENERICO;

        // EMAIL_DUPLICADO apunta a un campo concreto, así que el
        // mensaje va ahí y no se repite abajo. El mismo texto dos
        // veces hace pensar que son dos problemas distintos.
        if (error.codigo === 'EMAIL_DUPLICADO' && $('f-email')) {
            const campoEmail = $('f-email');
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

    async function cargar() {
        try {
            // Los dos pedidos salen a la vez y se espera a los dos:
            // uno detrás del otro tardaría el doble sin necesidad.
            const [carreras, alumnos] = await Promise.all([
                api('GET', API_CARRERAS),
                api('GET', API_ALUMNOS)
            ]);

            if (!carreras.ok || !alumnos.ok) {
                fallaDeCarga('No pudimos cargar los datos. Recargá la página.');
                return;
            }

            estado.carreras = carreras.cuerpo.data || [];
            estado.alumnos = alumnos.cuerpo.data || [];
            pintar();
        } catch (e) {
            fallaDeCarga('No pudimos conectarnos con el servidor.');
        }
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

        const texto = [
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
        const td = document.createElement('td');
        td.dataset.etiqueta = etiqueta;

        if (texto === null || texto === undefined || texto === '') {
            const vacia = document.createElement('span');
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
        const td = document.createElement('td');
        td.dataset.etiqueta = 'Carreras';

        const lista = alumno.carreras || [];

        if (lista.length === 0) {
            const ninguna = document.createElement('span');
            ninguna.className = 'sin-dato';
            ninguna.textContent = 'sin carreras';
            td.appendChild(ninguna);
            return td;
        }

        const envoltorio = document.createElement('div');
        envoltorio.className = 'etiquetas';

        lista.forEach(function (carrera) {
            const etiqueta = document.createElement('span');
            etiqueta.className = 'etiqueta';
            etiqueta.textContent = carrera.carrera_nombre;
            envoltorio.appendChild(etiqueta);
        });

        td.appendChild(envoltorio);
        return td;
    }

    function celdaAcciones(alumno) {
        const td = document.createElement('td');
        td.dataset.etiqueta = 'Acciones';

        const envoltorio = document.createElement('div');
        envoltorio.className = 'acciones';

        [
            { accion: 'carreras', texto: 'Carreras', clase: '' },
            { accion: 'editar', texto: 'Editar', clase: '' },
            { accion: 'baja', texto: 'Baja', clase: 'peligro' }
        ].forEach(function (spec) {
            const boton = document.createElement('button');
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
        const filtro = buscar.value.trim().toLowerCase();

        const visibles = estado.alumnos.filter(function (a) {
            return coincide(a, filtro);
        });

        cuerpo.textContent = '';

        visibles.forEach(function (alumno) {
            const tr = document.createElement('tr');
            tr.appendChild(celda(alumno.nombre, 'Nombre', 'nombre-alumno'));
            tr.appendChild(celda(alumno.email, 'Email'));
            tr.appendChild(celda(alumno.telefono, 'Teléfono'));
            tr.appendChild(celda(alumno.nacionalidad, 'Nacionalidad'));
            tr.appendChild(celdaCarreras(alumno));
            tr.appendChild(celdaAcciones(alumno));
            cuerpo.appendChild(tr);
        });

        const total = estado.alumnos.length;

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

        const vacia = document.createElement('option');
        vacia.value = '';
        vacia.textContent = textoVacio;
        select.appendChild(vacia);

        carreras.forEach(function (carrera) {
            const opcion = document.createElement('option');
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
        const alumno = estado.alumnos.find(function (a) { return a.id === id; });
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

    async function guardarAlumno(evento) {
        evento.preventDefault();
        limpiarErroresFormulario();

        const datos = {
            nombre: $('f-nombre').value.trim(),
            email: $('f-email').value.trim(),
            telefono: $('f-telefono').value.trim(),
            nacionalidad: $('f-nacionalidad').value.trim()
        };

        const esAlta = estado.editando === null;
        if (esAlta) {
            datos.carrera_id = $('f-carrera_id').value;
        }

        const boton = $('guardar');
        boton.disabled = true;

        try {
            const resultado = esAlta
                ? await api('POST', API_ALUMNOS, datos)
                : await api('PUT', API_ALUMNOS + '?id=' + encodeURIComponent(estado.editando), datos);

            if (resultado.ok && resultado.cuerpo && resultado.cuerpo.ok) {
                dlgAlumno.close();
                mostrarAviso(esAlta ? 'Alumno dado de alta.' : 'Cambios guardados.');
                await cargar();
            } else {
                pintarError(resultado, $('error-alumno'));
            }
        } catch (e) {
            $('error-alumno').textContent = 'No pudimos conectarnos con el servidor.';
        } finally {
            boton.disabled = false;
        }
    }

    /* --- Carreras de un alumno ----------------------------------------- */

    function abrirCarreras(id) {
        const alumno = estado.alumnos.find(function (a) { return a.id === id; });
        if (!alumno) { return; }

        estado.gestionando = alumno;
        $('error-carreras').textContent = '';
        $('carreras-alumno').textContent = alumno.nombre;

        pintarCarrerasDelAlumno();

        dlgCarreras.showModal();
    }

    function pintarCarrerasDelAlumno() {
        const alumno = estado.gestionando;
        const lista = $('lista-carreras');
        lista.textContent = '';

        const suyas = alumno.carreras || [];

        if (suyas.length === 0) {
            const li = document.createElement('li');
            li.className = 'ninguna';
            li.textContent = 'No está inscripto a ninguna carrera.';
            lista.appendChild(li);
        } else {
            suyas.forEach(function (carrera) {
                const li = document.createElement('li');

                const nombre = document.createElement('span');
                nombre.textContent = carrera.carrera_nombre;
                li.appendChild(nombre);

                const quitar = document.createElement('button');
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
        const yaTiene = suyas.map(function (c) { return c.carrera_id; });
        const disponibles = estado.carreras.filter(function (c) {
            return c.activa && yaTiene.indexOf(c.id) === -1;
        });

        llenarSelect(
            $('f-nueva-carrera'),
            disponibles,
            disponibles.length ? 'Elegí una carrera…' : 'No quedan carreras para agregar'
        );
        $('agregar-carrera').disabled = disponibles.length === 0;
    }

    async function refrescarGestionando() {
        await cargar();

        if (!estado.gestionando) { return; }

        const actualizado = estado.alumnos.find(function (a) {
            return a.id === estado.gestionando.id;
        });

        if (actualizado) {
            estado.gestionando = actualizado;
            pintarCarrerasDelAlumno();
        }
    }

    async function agregarCarrera() {
        const carreraId = $('f-nueva-carrera').value;
        $('error-carreras').textContent = '';

        if (!carreraId) {
            $('error-carreras').textContent = 'Elegí una carrera.';
            return;
        }

        const boton = $('agregar-carrera');
        boton.disabled = true;

        try {
            const resultado = await api('POST', API_INSCRIPCIONES, {
                alumno_id: estado.gestionando.id,
                carrera_id: carreraId
            });

            if (resultado.ok && resultado.cuerpo && resultado.cuerpo.ok) {
                mostrarAviso('Carrera asignada.');
                await refrescarGestionando();
            } else {
                const error = (resultado.cuerpo && resultado.cuerpo.error) || {};
                $('error-carreras').textContent = error.mensaje || MENSAJE_GENERICO;
            }
        } catch (e) {
            $('error-carreras').textContent = 'No pudimos conectarnos con el servidor.';
        } finally {
            boton.disabled = false;
        }
    }

    async function quitarCarrera(inscripcionId) {
        $('error-carreras').textContent = '';

        try {
            const resultado = await api(
                'DELETE',
                API_INSCRIPCIONES + '?id=' + encodeURIComponent(inscripcionId)
            );

            if (resultado.ok && resultado.cuerpo && resultado.cuerpo.ok) {
                mostrarAviso('Carrera quitada.');
                await refrescarGestionando();
            } else {
                const error = (resultado.cuerpo && resultado.cuerpo.error) || {};
                $('error-carreras').textContent = error.mensaje || MENSAJE_GENERICO;
            }
        } catch (e) {
            $('error-carreras').textContent = 'No pudimos conectarnos con el servidor.';
        }
    }

    /* --- Baja ----------------------------------------------------------- */

    function abrirBaja(id) {
        const alumno = estado.alumnos.find(function (a) { return a.id === id; });
        if (!alumno) { return; }

        estado.dandoBaja = alumno;
        $('error-baja').textContent = '';
        $('texto-baja').textContent =
            '¿Confirmás dar de baja a ' + alumno.nombre + ' (' + alumno.email + ')?';

        dlgBaja.showModal();
    }

    async function confirmarBaja() {
        const boton = $('confirmar-baja');
        boton.disabled = true;

        try {
            const resultado = await api(
                'DELETE',
                API_ALUMNOS + '?id=' + encodeURIComponent(estado.dandoBaja.id)
            );

            if (resultado.ok && resultado.cuerpo && resultado.cuerpo.ok) {
                dlgBaja.close();
                mostrarAviso('Alumno dado de baja.');
                await cargar();
            } else {
                const error = (resultado.cuerpo && resultado.cuerpo.error) || {};
                $('error-baja').textContent = error.mensaje || MENSAJE_GENERICO;
            }
        } catch (e) {
            $('error-baja').textContent = 'No pudimos conectarnos con el servidor.';
        } finally {
            boton.disabled = false;
        }
    }

    /* --- Cableado --------------------------------------------------------- */

    // Los botones de cada fila se crean y se destruyen en cada
    // pintado, así que el listener va en el tbody y no en cada botón.
    cuerpo.addEventListener('click', function (evento) {
        const boton = evento.target.closest('button[data-accion]');
        if (!boton) { return; }

        const id = Number(boton.dataset.id);
        limpiarAvisos();

        if (boton.dataset.accion === 'editar') { abrirEdicion(id); }
        if (boton.dataset.accion === 'carreras') { abrirCarreras(id); }
        if (boton.dataset.accion === 'baja') { abrirBaja(id); }
    });

    $('lista-carreras').addEventListener('click', function (evento) {
        const boton = evento.target.closest('button[data-inscripcion]');
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
