@php
    $valor = $fila->{$campo} ?? null;
@endphp
@if($campo === 'estado')
    <x-estado-participacion :estado="$valor" />
@elseif($campo === 'titulo')
    <a href="{{ \App\Support\Regreso::enlace(route('seguimiento.show', $fila->proyecto_id ?? $fila->id)) }}">{{ $valor }}</a>
@elseif($campo === 'nombre' && $tipo === 'carga_profesores')
    <a href="{{ \App\Support\Regreso::enlace(route('cuentas.edit', $fila->profesor_id)) }}">{{ $valor }}</a>
@elseif($campo === 'tipo')
    {{ $valor === 'alumno' ? 'Alumno' : 'Dirección' }}
@elseif(in_array($campo, ['fecha_solicitud','inicio','fin'], true))
    @if($valor)<x-fecha-local :valor="$valor" />@else{{ $campo === 'fin' ? 'Sin fecha final' : 'Sin registrar' }}@endif
@elseif($valor === null)
    Sin registrar
@else
    {{ $valor }}
@endif
