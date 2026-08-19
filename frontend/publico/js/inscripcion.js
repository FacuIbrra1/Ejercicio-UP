/* =====================================================================
   Formulario público de inscripción.

   La validación de acá solo da respuesta inmediata. La que manda es
   la del servidor, que no se puede saltear con curl ni desactivando
   JavaScript.

   Nada se inserta con innerHTML: siempre textContent, así un dato con
   < o > se muestra como texto y no se interpreta como HTML.
   ===================================================================== */

(function () {
    'use strict';

    const API_CARRERAS = 'api/carreras.cgi';
    const API_INSCRIPCIONES = 'api/inscripciones.cgi';

    const formulario = document.getElementById('formulario');
    const selectCarrera = document.getElementById('carrera_id');
    const botonEnviar = document.getElementById('enviar');
    const alerta = document.getElementById('alerta');
    const panelFormulario = document.getElementById('panel-formulario');
    const panelExito = document.getElementById('panel-exito');
    const exitoDetalle = document.getElementById('exito-detalle');
    const botonOtra = document.getElementById('otra');

    const CAMPOS = ['nombre', 'email', 'telefono', 'nacionalidad', 'carrera_id'];

    const MENSAJE_GENERICO =
        'No pudimos procesar tu inscripción. Probá de nuevo en unos minutos.';

    function comportamientoScroll() {
        const prefiereQuieto = window.matchMedia
            && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        return prefiereQuieto ? 'auto' : 'smooth';
    }

    /* --- Avisos ---------------------------------------------------- */

    function mostrarAlerta(titulo, detalle) {
        alerta.textContent = '';

        const fuerte = document.createElement('strong');
        fuerte.textContent = titulo;
        alerta.appendChild(fuerte);

        if (detalle) {
            alerta.appendChild(document.createTextNode(detalle));
        }

        alerta.hidden = false;
        alerta.scrollIntoView({ behavior: comportamientoScroll(), block: 'nearest' });
    }

    function ocultarAlerta() {
        alerta.hidden = true;
        alerta.textContent = '';
    }

    /* --- Errores por campo ----------------------------------------- */

    function limpiarErrores() {
        CAMPOS.forEach(function (campo) {
            const entrada = document.getElementById(campo);
            const destino = document.getElementById('error-' + campo);

            if (entrada) {
                entrada.classList.remove('invalido');
                entrada.removeAttribute('aria-invalid');
            }
            if (destino) {
                destino.textContent = '';
            }
        });
    }

    function pintarErrores(campos) {
        // El único que se reasigna: guarda el primer campo con error
        // para llevarle el foco al terminar el recorrido.
        let primero = null;

        Object.keys(campos || {}).forEach(function (campo) {
            const entrada = document.getElementById(campo);
            const destino = document.getElementById('error-' + campo);

            if (entrada) {
                entrada.classList.add('invalido');
                entrada.setAttribute('aria-invalid', 'true');
                if (!primero) {
                    primero = entrada;
                }
            }
            if (destino) {
                destino.textContent = campos[campo];
            }
        });

        // Llevar el foco al primer campo con problema le ahorra al
        // usuario tener que buscar cuál falló.
        if (primero) {
            primero.focus();
        }
    }

    /* --- Validación en el cliente ----------------------------------- */
    /* Refleja las reglas de UP::Service::Validacion. Si las dos se
       separan, la del servidor es la que vale. */

    function validar(datos) {
        const errores = {};

        if (!datos.nombre) {
            errores.nombre = 'El nombre es obligatorio.';
        } else if (datos.nombre.length < 2) {
            errores.nombre = 'El nombre es demasiado corto.';
        }

        if (!datos.email) {
            errores.email = 'El email es obligatorio.';
        } else if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(datos.email)) {
            errores.email = 'El email no tiene un formato válido.';
        }

        if (datos.telefono) {
            if (!/^[0-9+()\-\s]+$/.test(datos.telefono)) {
                errores.telefono =
                    'El teléfono solo puede tener números, espacios y los signos + - ( ).';
            } else if (datos.telefono.replace(/[^0-9]/g, '').length < 6) {
                errores.telefono = 'El teléfono es demasiado corto.';
            }
        }

        if (!datos.carrera_id) {
            errores.carrera_id = 'Elegí una carrera.';
        }

        return errores;
    }

    function leerFormulario() {
        function valor(id) {
            return document.getElementById(id).value.trim().replace(/\s+/g, ' ');
        }

        return {
            nombre: valor('nombre'),
            email: valor('email'),
            telefono: valor('telefono'),
            nacionalidad: valor('nacionalidad'),
            carrera_id: valor('carrera_id')
        };
    }

    /* --- Carga de carreras ------------------------------------------ */

    async function cargarCarreras() {
        try {
            const respuesta = await fetch(API_CARRERAS, {
                headers: { Accept: 'application/json' }
            });
            const cuerpo = await respuesta.json();

            if (!cuerpo || !cuerpo.ok || !Array.isArray(cuerpo.data)) {
                throw new Error('respuesta inesperada');
            }

            selectCarrera.textContent = '';

            const vacia = document.createElement('option');
            vacia.value = '';
            vacia.textContent = 'Elegí una carrera…';
            selectCarrera.appendChild(vacia);

            cuerpo.data.forEach(function (carrera) {
                const opcion = document.createElement('option');
                opcion.value = carrera.id;
                opcion.textContent = carrera.nombre;
                selectCarrera.appendChild(opcion);
            });
        } catch (e) {
            selectCarrera.textContent = '';

            const opcion = document.createElement('option');
            opcion.value = '';
            opcion.textContent = 'No se pudieron cargar las carreras';
            selectCarrera.appendChild(opcion);

            botonEnviar.disabled = true;

            mostrarAlerta(
                'No pudimos cargar las carreras. ',
                'Recargá la página para volver a intentarlo.'
            );
        }
    }

    /* --- Envío ------------------------------------------------------- */

    function manejarErrorDelServidor(cuerpo) {
        const error = (cuerpo && cuerpo.error) || {};

        switch (error.codigo) {
            case 'VALIDACION':
                pintarErrores(error.campos);
                mostrarAlerta('Revisá los datos marcados. ', '');
                break;

            // El caso que pide la consigna: ya existe esa inscripción.
            case 'ALUMNO_YA_INSCRIPTO':
                mostrarAlerta('Ya estás inscripto. ', error.mensaje);
                break;

            // El detalle se muestra junto al campo email y la alerta
            // solo encabeza, sin repetir la misma frase: el mismo texto
            // dos veces en la pantalla no agrega información y hace
            // pensar que son dos problemas distintos.
            case 'EMAIL_DUPLICADO':
                pintarErrores({ email: error.mensaje });
                mostrarAlerta('Revisá los datos marcados. ', '');
                break;

            case 'CARRERA_INVALIDA':
                mostrarAlerta('Esa carrera ya no está disponible. ', error.mensaje);
                cargarCarreras();
                break;

            default:
                mostrarAlerta('No pudimos procesar tu inscripción. ',
                    error.mensaje || MENSAJE_GENERICO);
        }
    }

    function mostrarExito(datos, email) {
        exitoDetalle.textContent =
            'Registramos tu inscripción a ' + datos.carrera +
            '. Te vamos a escribir a ' + email + ' con los pasos siguientes.';

        panelFormulario.hidden = true;
        panelExito.hidden = false;
        ocultarAlerta();
        panelExito.scrollIntoView({ behavior: comportamientoScroll(), block: 'nearest' });
    }

    async function enviar(evento) {
        evento.preventDefault();

        ocultarAlerta();
        limpiarErrores();

        const datos = leerFormulario();
        const errores = validar(datos);

        if (Object.keys(errores).length > 0) {
            pintarErrores(errores);
            return;
        }

        botonEnviar.disabled = true;
        botonEnviar.textContent = 'Enviando…';

        try {
            const respuesta = await fetch(API_INSCRIPCIONES, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    Accept: 'application/json'
                },
                body: JSON.stringify(datos)
            });

            // Si el servidor devolviera una página de error de Apache
            // en vez de JSON, .json() explota. Se atrapa acá para
            // mostrar un mensaje entendible y no un "Unexpected token
            // <" en la consola.
            let cuerpo = null;
            try {
                cuerpo = await respuesta.json();
            } catch (e) {
                cuerpo = null;
            }

            if (respuesta.ok && cuerpo && cuerpo.ok) {
                mostrarExito(cuerpo.data, datos.email);
            } else {
                manejarErrorDelServidor(cuerpo);
            }
        } catch (e) {
            // Sin red, servidor caído o pedido cancelado.
            mostrarAlerta('No pudimos conectarnos con el servidor. ',
                'Revisá tu conexión y volvé a intentar.');
        } finally {
            // finally corre pase lo que pase, así que el botón se
            // rehabilita incluso si algo falló arriba.
            botonEnviar.disabled = false;
            botonEnviar.textContent = 'Enviar inscripción';
        }
    }

    /* --- Volver al formulario ---------------------------------------- */

    function otraInscripcion() {
        // Se conservan los datos personales y solo se limpia la
        // carrera: quien se anota a una segunda carrera no tiene por
        // qué escribir todo de nuevo.
        selectCarrera.value = '';

        limpiarErrores();
        ocultarAlerta();

        panelExito.hidden = true;
        panelFormulario.hidden = false;

        selectCarrera.focus();
    }

    /* --- Arranque ----------------------------------------------------- */

    formulario.addEventListener('submit', enviar);
    botonOtra.addEventListener('click', otraInscripcion);

    // Al corregir un campo marcado, se le saca la marca en el momento.
    CAMPOS.forEach(function (campo) {
        const entrada = document.getElementById(campo);
        if (!entrada) {
            return;
        }
        entrada.addEventListener('input', function () {
            entrada.classList.remove('invalido');
            entrada.removeAttribute('aria-invalid');
            const destino = document.getElementById('error-' + campo);
            if (destino) {
                destino.textContent = '';
            }
        });
    });

    cargarCarreras();
})();
