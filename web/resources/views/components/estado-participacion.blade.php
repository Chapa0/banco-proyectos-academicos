@props(['estado'])
@php
    $etiquetas = ['pendiente_evaluacion' => 'Pendiente de evaluación', 'pendiente' => 'Pendiente', 'evaluada' => 'Evaluada', 'preseleccionada' => 'Preseleccionada', 'aprobada' => 'Aprobada', 'rechazada' => 'Rechazada', 'cancelada' => 'Cancelada', 'vigente' => 'Vigente', 'finalizada' => 'Finalizada', 'revocada' => 'Revocada', 'borrador' => 'Borrador', 'en_revision' => 'En revisión', 'en_correccion' => 'En corrección', 'publicado' => 'Publicado', 'en_curso' => 'En curso', 'pausado' => 'Pausado', 'finalizado' => 'Finalizado', 'cancelado' => 'Cancelado', 'rechazado' => 'Rechazado'];
    $clase = in_array($estado, ['rechazada','cancelada','revocada','rechazado','cancelado']) ? 'status-rejected' : 'status-active';
@endphp
<span class="status-badge {{ $clase }}">{{ $etiquetas[$estado] ?? $estado }}</span>
