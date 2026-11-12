@foreach(['alumnos' => ['Alumnos', 'retirar_alumno'], 'directores' => ['Dirección', 'retirar_director']] as $grupo => [$titulo, $accionRetiro])
    @if(! $detalle->vacante || count($detalle->{$grupo}))
    <section class="surface mt-4" aria-labelledby="asignaciones-{{ $grupo }}"><h2 class="section-heading" id="asignaciones-{{ $grupo }}">{{ $titulo }}</h2>
        @forelse($detalle->{$grupo} as $asignacion)
            <article class="revision-entry account-summary">
                <h3 class="h6">{{ $asignacion->nombre }}</h3><x-estado-participacion :estado="$asignacion->estado" />
                <p class="field-hint mt-3 mb-1">Desde: <x-fecha-local :valor="$asignacion->inicio" />@if($asignacion->fin) · Hasta: <x-fecha-local :valor="$asignacion->fin" />@endif</p>
                @if($asignacion->perfil)<details class="revision-entry"><summary>Consultar perfil</summary><div class="pt-3">@include('participacion._perfil', ['perfil' => $asignacion->perfil])</div></details>@endif
                @if($asignacion->estado === 'vigente' && in_array($accionRetiro, $detalle->acciones, true))
                    <details class="revision-entry" @if(is_scalar(old('asignacion_id', '')) && (string) old('asignacion_id', '') === (string) $asignacion->id && $errors->any()) open @endif><summary>{{ $grupo === 'alumnos' ? 'Retirar alumno' : 'Retirar director' }}</summary><form class="pt-3" method="POST" action="{{ route('seguimiento.operar', ['proyecto' => $detalle->proyecto->id, 'accion' => $accionRetiro]) }}" data-submit-label="Registrando retiro…">@csrf @include('participacion._version', ['version' => $detalle->version])<input type="hidden" name="asignacion_id" value="{{ $asignacion->id }}"><p>El retiro conserva el historial y libera esta asignación. Si el proyecto en curso pierde su mínimo de participantes, quedará pausado.</p><x-campo name="motivo" :input-id="'motivo-'.$grupo.'-'.$asignacion->id" label="Motivo del retiro" type="textarea" maxlength="1000" required placeholder="Ej. El alumno dio de baja la materia de residencia." info="Queda registrado en el historial. Si el proyecto se queda sin el mínimo de participantes, se pausará." /><button class="btn btn-outline-danger" type="submit">Confirmar retiro</button></form></details>
                @endif
            </article>
        @empty
            <p class="text-body-secondary mb-0">No hay asignaciones de este tipo disponibles para tu consulta.</p>
        @endforelse
    </section>
    @endif
@endforeach
