@props(['proyectos', 'titulo' => 'Recomendados para ti', 'nivel' => 'h2', 'logos' => []])
{{-- «Recomendados para ti» (UX-06): orienta según el perfil; no decide ni bloquea candidaturas. --}}
@if(count($proyectos))
    <section {{ $attributes->class(['recommendations']) }} aria-labelledby="recomendados-titulo">
        <div class="recommendations-header">
            <{{ $nivel }} id="recomendados-titulo" class="section-heading mb-1">{{ $titulo }}</{{ $nivel }}>
            <p class="field-hint mb-0">Según las habilidades de tu perfil. Solo incluye proyectos con plazas libres en los que aún no participas.</p>
        </div>
        <ol class="recommendation-list">
            @foreach($proyectos as $proyecto)
                <li class="recommendation-card">
                    <h3 class="recommendation-title"><a href="{{ \App\Support\Regreso::enlace(route('catalogo.show', $proyecto->id)) }}">{{ $proyecto->titulo }}</a></h3>
                    <p class="recommendation-company company-line"><x-avatar :imagen="$logos[$proyecto->id] ?? null" :nombre="$proyecto->razon_social" tamano="sm" logo />{{ $proyecto->razon_social }}@if($proyecto->modalidad) · {{ $proyecto->modalidad }}@endif</p>
                    <x-coincidencia :datos="$proyecto->coincidencia" compacta />
                    <p class="recommendation-seats mb-0">{{ $proyecto->plazas_disponibles }} de {{ $proyecto->cupo_maximo_alumnos }} {{ $proyecto->cupo_maximo_alumnos === 1 ? 'plaza libre' : 'plazas libres' }}</p>
                </li>
            @endforeach
        </ol>
    </section>
@endif
