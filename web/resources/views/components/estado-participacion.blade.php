@props(['estado'])
@php
    $etiquetas = ['pendiente_evaluacion' => 'Pendiente de evaluación', 'pendiente' => 'Pendiente', 'evaluada' => 'Evaluada', 'preseleccionada' => 'Preseleccionada', 'aprobada' => 'Aprobada', 'rechazada' => 'Rechazada', 'cancelada' => 'Cancelada', 'vigente' => 'Vigente', 'finalizada' => 'Finalizada', 'revocada' => 'Revocada', 'borrador' => 'Borrador', 'en_revision' => 'En revisión', 'en_correccion' => 'En corrección', 'publicado' => 'Publicado', 'en_curso' => 'En curso', 'pausado' => 'Pausado', 'finalizado' => 'Finalizado', 'cancelado' => 'Cancelado', 'rechazado' => 'Rechazado'];
@endphp
@php
    $tono = match (true) {
        in_array($estado, ['publicado', 'aprobada', 'vigente', 'en_curso', 'finalizado', 'finalizada'], true) => ['status-active', 'bi-check-circle-fill'],
        in_array($estado, ['rechazado', 'rechazada', 'cancelado', 'cancelada', 'revocada'], true) => ['status-rejected', 'bi-x-circle-fill'],
        in_array($estado, ['en_revision', 'pendiente', 'pendiente_evaluacion', 'evaluada', 'preseleccionada', 'en_correccion', 'pausado'], true) => ['status-pending', 'bi-hourglass-split'],
        default => ['status-inactive', 'bi-circle'],
    };
@endphp
<span class="status-badge {{ $tono[0] }}"><i class="bi {{ $tono[1] }}" aria-hidden="true"></i>{{ $etiquetas[$estado] ?? $estado }}</span>
