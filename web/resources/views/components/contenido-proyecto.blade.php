@props(['contenido', 'habilidades' => [], 'cupoLabel' => 'Cupo propuesto de alumnos'])
<dl class="project-details">
    @foreach(['descripcion' => 'Descripción', 'problematica' => 'Problemática', 'objetivos' => 'Objetivos', 'justificacion' => 'Justificación', 'alcance' => 'Alcance', 'cupo_maximo_alumnos' => 'Cupo propuesto de alumnos', 'requisitos_academicos' => 'Requisitos académicos', 'duracion_estimada' => 'Duración estimada', 'modalidad' => 'Modalidad', 'fecha_inicio_estimada' => 'Inicio estimado', 'fecha_fin_estimada' => 'Fin estimado', 'recursos' => 'Recursos disponibles'] as $campo => $etiqueta)
        @if(! in_array($campo, ['requisitos_academicos','duracion_estimada','modalidad','fecha_inicio_estimada','fecha_fin_estimada','recursos']) || (isset($contenido->{$campo}) && $contenido->{$campo} !== ''))
            <div><dt>{{ $campo === 'cupo_maximo_alumnos' ? $cupoLabel : $etiqueta }}</dt><dd class="preserve-lines">{{ isset($contenido->{$campo}) && $contenido->{$campo} !== '' ? $contenido->{$campo} : 'Sin registrar' }}</dd></div>
        @endif
    @endforeach
</dl>
<h3 class="h6 mt-4">Habilidades deseadas</h3>
@forelse($habilidades as $habilidad)
    <div class="project-skill"><p class="fw-semibold mb-1">{{ $habilidad->nombre }} <span class="field-hint fw-normal">({{ $habilidad->tipo === 'dura' ? 'dura' : 'blanda' }})</span></p><p class="mb-0 small">Nivel esperado: {{ $habilidad->nivel_minimo ?: 'Sin especificar' }} · {{ $habilidad->obligatoria ? 'Obligatoria' : 'Deseable' }}</p></div>
@empty
    <p class="text-body-secondary mb-0">No se indicaron habilidades.</p>
@endforelse
