@props(['datos', 'sujeto' => 'tu', 'compacta' => false])
{{-- Coincidencia de habilidades (UX-02). Orienta: no bloquea ni reemplaza la evaluación. --}}
@php
    $verbo = $sujeto === 'tu' ? 'Cumples' : 'Cumple';
    $faltan = collect($datos->faltantes);
@endphp
<div {{ $attributes->class(['skill-match', 'skill-match-'.$datos->nivel, 'is-compact' => $compacta]) }}>
    <p class="skill-match-title mb-1">
        <span class="skill-match-count">{{ $verbo }} {{ $datos->cumplidas }} de {{ $datos->requeridas }}</span>
        {{ $datos->requeridas === 1 ? 'habilidad solicitada' : 'habilidades solicitadas' }}
    </p>
    <div class="skill-match-bar" aria-hidden="true"><span style="width: {{ $datos->requeridas ? round($datos->cumplidas * 100 / $datos->requeridas) : 0 }}%"></span></div>
    @if($faltan->isNotEmpty())
        <p class="skill-match-missing mb-0">
            {{ $sujeto === 'tu' ? 'Te falta' : 'Le falta' }}{{ $faltan->count() > 1 ? 'n' : '' }}:
            @foreach($faltan->take($compacta ? 3 : 20) as $f){{ $f->nombre }}@if($f->obligatoria) <strong>(obligatoria)</strong>@endif{{ $loop->last ? '' : ', ' }}@endforeach
            @if($compacta && $faltan->count() > 3) y {{ $faltan->count() - 3 }} más @endif
        </p>
    @endif
</div>
