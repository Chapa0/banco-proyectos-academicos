@props(['carga', 'profesores' => 0])
{{-- UX-09: lista de medidores, uno por profesor con dirección vigente, frente al límite de tres (D-04). --}}
<figure {{ $attributes->class(['chart-card']) }} aria-labelledby="carga-titulo">
    <figcaption class="chart-header">
        <h3 class="chart-title" id="carga-titulo">Carga de profesores</h3>
        <p class="chart-total">{{ count($carga) }} de {{ $profesores }} con proyectos vigentes</p>
    </figcaption>
    @if(count($carga))
        <ul class="meter-list">
            @foreach(array_slice($carga, 0, 8) as $p)
                @php $lleno = $p->vigentes >= $p->limite; @endphp
                <li class="meter-row" title="{{ $p->nombre }}: {{ $p->vigentes }} de {{ $p->limite }} proyectos">
                    <a class="bar-label" href="{{ route('reportes.index', ['carga_profesores', 'profesor_id' => $p->profesor_id]) }}">{{ $p->nombre }}</a>
                    <span class="meter-track" aria-hidden="true"><span class="meter-fill" style="width: {{ min(100, $p->vigentes * 100 / max(1, $p->limite)) }}%"></span></span>
                    <span class="bar-value">{{ $p->vigentes }} de {{ $p->limite }}@if($lleno) <span class="meter-flag">· al límite</span>@endif</span>
                </li>
            @endforeach
        </ul>
        @if(count($carga) > 8)<p class="field-hint mb-0 mt-2">Y {{ count($carga) - 8 }} más en el reporte de carga.</p>@endif
    @else
        <p class="field-hint mb-0">Ningún profesor dirige proyectos vigentes.</p>
    @endif
</figure>
