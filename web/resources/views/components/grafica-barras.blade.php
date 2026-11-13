@props(['id', 'titulo', 'unidad' => ['registro', 'registros'], 'filas'])
{{-- UX-09: barras horizontales de una sola serie (magnitud por categoría). El texto (categoría y valor)
     es el dato; la barra solo lo refuerza, así que se lee igual sin color y con lector de pantalla.
     Cada fila enlaza al reporte filtrado por esa categoría. --}}
@php
    $maximo = max(1, ...array_map(fn ($f) => (int) $f['valor'], $filas));
    $total = array_sum(array_map(fn ($f) => (int) $f['valor'], $filas));
@endphp
<figure {{ $attributes->class(['chart-card']) }} aria-labelledby="{{ $id }}-titulo">
    <figcaption class="chart-header">
        <h3 class="chart-title" id="{{ $id }}-titulo">{{ $titulo }}</h3>
        <p class="chart-total">{{ $total }} {{ $total === 1 ? $unidad[0] : $unidad[1] }}</p>
    </figcaption>
    <ul class="bar-chart">
        @foreach($filas as $fila)
            @php
                $valor = (int) $fila['valor'];
                $porcentaje = $total ? round($valor * 100 / $total) : 0;
                $detalle = $fila['etiqueta'].': '.$valor.' '.($valor === 1 ? $unidad[0] : $unidad[1]).' ('.$porcentaje.' %)';
            @endphp
            <li class="bar-row {{ $valor === 0 ? 'is-zero' : '' }}" title="{{ $detalle }}">
                <a class="bar-label" href="{{ $fila['url'] }}" aria-label="{{ $detalle }}. Abrir el reporte filtrado">{{ $fila['etiqueta'] }}</a>
                <span class="bar-track" aria-hidden="true"><span class="bar-fill" style="width: {{ $valor ? max(1.5, $valor * 100 / $maximo) : 0 }}%"></span></span>
                <span class="bar-value" aria-hidden="true">{{ $valor }}</span>
            </li>
        @endforeach
    </ul>
</figure>
