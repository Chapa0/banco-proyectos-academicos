@props(['avance', 'enlazar' => false])
{{-- Avance del perfil propio (UX-02): orienta sin bloquear. --}}
<div {{ $attributes->class(['profile-progress']) }}>
    <div class="profile-progress-header">
        <p class="mb-0 fw-semibold" id="avance-perfil-texto">Perfil completo al {{ $avance->porcentaje }} %</p>
        @if($avance->porcentaje === 100)<span class="status-badge status-active">Completo</span>@endif
    </div>
    <div class="skill-match-bar profile-progress-bar" role="progressbar" aria-labelledby="avance-perfil-texto" aria-valuemin="0" aria-valuemax="100" aria-valuenow="{{ $avance->porcentaje }}"><span style="width: {{ $avance->porcentaje }}%"></span></div>
    @if($avance->faltantes)
        <p class="field-hint mb-0">Un perfil completo ayuda a las empresas a evaluarte. Agrega:
            @foreach($avance->faltantes as $f)<a href="{{ $enlazar ? \App\Support\Regreso::enlace(route('perfil.edit').'#'.$f->campo) : '#'.$f->campo }}">{{ $f->texto }}</a>{{ $loop->last ? '.' : ($loop->remaining === 1 ? ' y ' : ', ') }}@endforeach
        </p>
    @endif
</div>
