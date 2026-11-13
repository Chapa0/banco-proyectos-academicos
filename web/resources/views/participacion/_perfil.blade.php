@php
    $docsPerfil = collect(($documentos ?? [])[$perfil->usuario_id ?? 0] ?? []);
    $cvPerfil = $docsPerfil->firstWhere('tipo', 'curriculum');
    $evidenciasPerfil = $docsPerfil->where('tipo', 'evidencia')->groupBy('habilidad_id');
@endphp
<div class="profile-heading"><x-avatar :imagen="(($imagenes->fotos ?? [])[$perfil->usuario_id ?? 0] ?? null)" :nombre="$perfil->nombre" tamano="lg" /><h2 class="section-heading mb-0">{{ $perfil->nombre }}</h2></div>
@if($perfil->perfil)
    <dl class="project-details">
        @foreach(['matricula' => 'Matrícula', 'numero_empleado' => 'Número de empleado', 'carrera' => 'Carrera', 'semestre' => 'Semestre', 'datos_academicos' => 'Formación y datos académicos', 'especialidad' => 'Especialidad', 'experiencia' => 'Experiencia', 'contacto_correo' => 'Correo de contacto', 'contacto_telefono' => 'Teléfono de contacto'] as $campo => $etiqueta)
            @if(isset($perfil->perfil->{$campo}) && $perfil->perfil->{$campo} !== '')
                <div><dt>{{ $etiqueta }}</dt><dd class="preserve-lines">{{ $perfil->perfil->{$campo} }}</dd></div>
            @endif
        @endforeach
        @if($cvPerfil)<div><dt>Currículum</dt><dd><x-documento-enlace :documento="$cvPerfil" /></dd></div>@endif
    </dl>
@else
    <p class="text-body-secondary">El perfil académico todavía no está completo.</p>
@endif
@if(count($perfil->habilidades ?? []))
    <h3 class="h6 mt-4">Habilidades</h3>
    @foreach($perfil->habilidades as $habilidad)
        <div class="project-skill"><p class="fw-semibold mb-1">{{ $habilidad->nombre }} <span class="field-hint fw-normal">({{ $habilidad->tipo === 'dura' ? 'dura' : 'blanda' }})</span></p><dl class="account-details mb-0 mt-2">@foreach(['nivel_dominio' => 'Nivel', 'descripcion' => 'Descripción', 'evidencia' => 'Evidencia'] as $campo => $etiqueta)@if(isset($habilidad->{$campo}) && $habilidad->{$campo} !== '')<div><dt>{{ $etiqueta }}</dt><dd class="preserve-lines">{{ $habilidad->{$campo} }}</dd></div>@endif @endforeach
            @if($evidenciasPerfil->has($habilidad->habilidad_id))<div><dt>Evidencias en PDF</dt><dd class="document-list">@foreach($evidenciasPerfil[$habilidad->habilidad_id] as $doc)<x-documento-enlace :documento="$doc" />@endforeach</dd></div>@endif
        </dl></div>
    @endforeach
@endif
