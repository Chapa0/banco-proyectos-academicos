@props(['pasos', 'titulo' => 'Avance'])
{{-- Línea de tiempo del estado (UX-06). Pasos calculados en App\Support\LineaTiempo. --}}
@php
    $textoEstado = ['hecho' => 'completado', 'actual' => 'paso actual', 'pendiente' => 'pendiente', 'detenido' => 'terminó aquí'];
@endphp
<nav {{ $attributes->class(['status-timeline']) }} aria-label="{{ $titulo }}">
    <ol class="status-timeline-list">
        @foreach($pasos as $paso)
            <li class="status-step is-{{ $paso['estado'] }}" @if($paso['estado'] === 'actual') aria-current="step" @endif>
                <span class="status-step-marker" aria-hidden="true"></span>
                <span class="status-step-body">
                    <span class="status-step-label">{{ $paso['etiqueta'] }}<span class="visually-hidden">: {{ $textoEstado[$paso['estado']] }}</span></span>
                    @if($paso['fecha'])<span class="status-step-date"><x-fecha-local :valor="$paso['fecha']" /></span>@endif
                </span>
            </li>
        @endforeach
    </ol>
</nav>
