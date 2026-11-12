<p class="field-hint mb-4">Para guardar el borrador basta con el título. Antes de enviar, completa los seis campos de contenido y el cupo de alumnos.</p>
<fieldset class="form-section">
    <legend>Contenido del proyecto</legend>
    <x-campo name="titulo" label="Título" :value="$proyecto->titulo ?? ''" required maxlength="250" placeholder="Ej. Sistema web para el control de inventario" info="Un nombre corto y claro que describa el resultado del proyecto. Es lo primero que verán alumnos y profesores en el catálogo." />
    @foreach([
        'descripcion' => ['Descripción', 'Ej. Aplicación web para registrar entradas y salidas de material del almacén y consultar existencias.', 'Explica en pocas líneas qué se va a construir y para quién.'],
        'problematica' => ['Problemática', 'Ej. El inventario se lleva en hojas de cálculo y se pierden registros de las salidas.', 'La situación actual que la empresa quiere resolver: qué falla o qué falta hoy.'],
        'objetivos' => ['Objetivos', 'Ej. Registrar movimientos en tiempo real y generar un reporte mensual de existencias.', 'Lo que el proyecto debe lograr al terminar. Conviene que sean concretos y medibles.'],
        'justificacion' => ['Justificación', 'Ej. Reducirá errores de captura y el tiempo dedicado a conteos manuales.', 'Por qué vale la pena hacer el proyecto: el beneficio para la empresa y el aprendizaje para los alumnos.'],
        'alcance' => ['Alcance', 'Ej. Incluye registro, consultas y reportes. No incluye facturación ni app móvil.', 'Qué entra y qué no entra en el proyecto. Ayuda a evitar malentendidos durante el desarrollo.'],
    ] as $campo => [$etiqueta, $ejemplo, $explicacion])
        <x-campo :name="$campo" :label="$etiqueta" type="textarea" :value="$proyecto->{$campo} ?? ''" maxlength="10000" rows="3" :placeholder="$ejemplo" :info="$explicacion" />
    @endforeach
    <x-campo name="cupo_maximo_alumnos" label="Cupo máximo de alumnos" type="number" :value="$proyecto->cupo_maximo_alumnos ?? ''" min="1" max="2147483647" placeholder="Ej. 3" inputmode="numeric" help="Propón cuántos alumnos admite el proyecto. El administrador deberá validar este cupo antes de publicarlo." />
</fieldset>
<fieldset class="form-section">
    <legend>Requisitos y planificación</legend>
    <p class="field-hint">Estos datos son opcionales.</p>
    <x-campo name="requisitos_academicos" label="Requisitos académicos" type="textarea" :value="$proyecto->requisitos_academicos ?? ''" maxlength="10000" rows="3" placeholder="Ej. Alumnos de 6.º semestre en adelante que hayan cursado Bases de datos." info="Condiciones académicas que deben cumplir los participantes, como semestre mínimo o materias aprobadas." />
    <div class="row"><div class="col-md-6"><x-campo name="duracion_estimada" label="Duración estimada" :value="$proyecto->duracion_estimada ?? ''" maxlength="250" placeholder="Ej. Cuatro meses" /></div><div class="col-md-6"><x-campo name="modalidad" label="Modalidad" :value="$proyecto->modalidad ?? ''" maxlength="250" placeholder="Ej. Presencial, remota o mixta" /></div></div>
    <div class="row"><div class="col-md-6"><x-campo name="fecha_inicio_estimada" label="Inicio estimado" type="date" :value="$proyecto->fecha_inicio_estimada ?? ''" /></div><div class="col-md-6"><x-campo name="fecha_fin_estimada" label="Fin estimado" type="date" :value="$proyecto->fecha_fin_estimada ?? ''" /></div></div>
    <x-campo name="recursos" label="Recursos disponibles" type="textarea" :value="$proyecto->recursos ?? ''" maxlength="10000" rows="3" placeholder="Ej. Equipo de cómputo en sitio, acceso a un servidor de pruebas y asesoría semanal." info="Lo que la empresa aporta para el desarrollo: equipo, software, espacio, datos de prueba o asesoría." />
</fieldset>
<fieldset class="form-section">
    <legend>Habilidades deseadas</legend>
    <p class="field-hint" id="habilidades-ayuda">Selecciona las habilidades del catálogo e indica el nivel esperado si lo necesitas. No hay un mínimo de habilidades requerido para enviar.</p>
    @php
        $seleccionadasIniciales = array_map(fn ($h) => (string) $h->habilidad_id, $proyecto->habilidades ?? []);
        $obligatoriasIniciales = array_map(fn ($h) => (string) $h->habilidad_id, array_filter($proyecto->habilidades ?? [], fn ($h) => $h->obligatoria));
        $seleccionadas = old('habilidades_seleccionadas', $seleccionadasIniciales);
        $seleccionadas = is_array($seleccionadas) ? $seleccionadas : [];
        $obligatorias = old('obligatorias', $obligatoriasIniciales);
        $obligatorias = is_array($obligatorias) ? $obligatorias : [];
        $nivelesAnteriores = old('niveles', []);
        $nivelesAnteriores = is_array($nivelesAnteriores) ? $nivelesAnteriores : [];
    @endphp
    @forelse($habilidades as $habilidad)
        @php
            $inicial = collect($proyecto->habilidades ?? [])->firstWhere('habilidad_id', $habilidad->id);
            $nivel = $nivelesAnteriores[$habilidad->id] ?? $inicial?->nivel_minimo ?? '';
        @endphp
        <div class="skill-row">
            <div class="form-check skill-selection">
                <input class="form-check-input" type="checkbox" name="habilidades_seleccionadas[]" id="habilidad-{{ $habilidad->id }}" value="{{ $habilidad->id }}" @checked(in_array((string) $habilidad->id, array_filter($seleccionadas, 'is_scalar'), false)) aria-describedby="habilidades-ayuda">
                <label class="form-check-label" for="habilidad-{{ $habilidad->id }}">{{ $habilidad->nombre }}<span class="d-block field-hint">{{ $habilidad->tipo === 'dura' ? 'Habilidad dura' : 'Habilidad blanda' }}</span></label>
            </div>
            <div><label class="form-label small" for="nivel-{{ $habilidad->id }}">Nivel esperado<span class="visually-hidden"> de {{ $habilidad->nombre }}</span></label><input class="form-control" type="text" id="nivel-{{ $habilidad->id }}" name="niveles[{{ $habilidad->id }}]" value="{{ is_scalar($nivel) ? $nivel : '' }}" maxlength="250" placeholder="Ej. Intermedio"></div>
            <div class="form-check skill-selection"><input class="form-check-input" type="checkbox" name="obligatorias[]" id="obligatoria-{{ $habilidad->id }}" value="{{ $habilidad->id }}" @checked(in_array((string) $habilidad->id, array_filter($obligatorias, 'is_scalar'), false))><label class="form-check-label" for="obligatoria-{{ $habilidad->id }}">Obligatoria<span class="visually-hidden">: {{ $habilidad->nombre }}</span></label></div>
        </div>
    @empty
        <p class="text-body-secondary">No hay habilidades disponibles en el catálogo. Puedes guardar y enviar el proyecto sin seleccionarlas.</p>
    @endforelse
</fieldset>
