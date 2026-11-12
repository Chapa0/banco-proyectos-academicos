<section class="surface mt-4" aria-labelledby="historial-titulo">
    <h2 class="section-heading" id="historial-titulo">Historial de revisiones</h2>
    @forelse($proyecto->revisiones as $revision)
        <details class="revision-entry">
            <summary>Revisión {{ $revision->numero }} <x-estado-proyecto :estado="$revision->estado_revision" /></summary>
            <div class="pt-3">
                <p class="field-hint">Enviada el {{ \Illuminate\Support\Carbon::parse($revision->fecha_envio)->format('d/m/Y H:i') }} UTC.</p>
                @if($revision->decision)
                    <p class="mb-1"><strong>Resolución:</strong> <x-estado-proyecto :estado="$revision->decision->resultado" /></p>
                    <p class="preserve-lines">{{ $revision->decision->justificacion }}</p>
                    <p class="field-hint">{{ $revision->decision->administrador_nombre }} · {{ \Illuminate\Support\Carbon::parse($revision->decision->fecha)->format('d/m/Y H:i') }} UTC.</p>
                @else
                    <p class="text-body-secondary">{{ $revision->estado_revision === 'en_revision' ? 'Pendiente de resolución administrativa.' : 'Esta revisión no tiene una resolución administrativa.' }}</p>
                @endif
                <h3 class="h6">{{ $revision->instantanea_contenido->proyecto->titulo }}</h3>
                <x-contenido-proyecto :contenido="$revision->instantanea_contenido->proyecto" :habilidades="$revision->instantanea_contenido->habilidades ?? []" />
            </div>
        </details>
    @empty
        <p class="text-body-secondary mb-0">El proyecto todavía no se ha enviado a revisión.</p>
    @endforelse
</section>
