@extends('layouts.app')
@section('title', 'Revisar proyecto · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <a class="back-link" href="{{ route('revision.index') }}">Volver a revisión de proyectos</a>
    <header class="page-header"><div><h1 class="page-title">{{ $proyecto->titulo }}</h1><p class="page-description">{{ $proyecto->empresa->razon_social }}</p></div><x-estado-proyecto :estado="$proyecto->estado" /></header>
    <x-errores />
    @if($puedeResolver)
        <p class="page-description mb-4">Revisa el contenido enviado y confirma el cupo antes de publicar. Si necesita cambios, devuelve el proyecto con observaciones.</p>
        <div class="row g-4">
            <div class="col-lg-8"><section class="surface" aria-labelledby="contenido-titulo"><h2 id="contenido-titulo" class="section-heading">Versión enviada · Revisión {{ $ultimaRevision->numero }}</h2><x-contenido-proyecto :contenido="$ultimaRevision->instantanea_contenido->proyecto" :habilidades="$ultimaRevision->instantanea_contenido->habilidades ?? []" /></section></div>
            <div class="col-lg-4"><section class="surface" aria-labelledby="resolver-titulo">
                <h2 id="resolver-titulo" class="section-heading">Resolver revisión</h2>
                <form method="POST" action="{{ route('revision.resolver', $proyecto->id) }}" data-submit-label="Guardando resolución…">
                    @csrf
                    <input type="hidden" name="version" value="{{ is_string(old('version', $proyecto->version)) ? old('version', $proyecto->version) : '' }}">
                    <input type="hidden" name="revision_id" value="{{ is_scalar(old('revision_id', $ultimaRevision->id)) ? old('revision_id', $ultimaRevision->id) : '' }}">
                    <div class="mb-4"><div class="label-row"><label class="form-label" for="resultado">Resolución<span class="required-mark" aria-hidden="true">*</span></label><x-info tema="Resolución" texto="Publicar: el proyecto aparece en el catálogo. Devolver: la empresa podrá corregirlo y reenviarlo. Rechazar: se cierra sin publicarse." /></div><select class="form-select @error('resultado') is-invalid @enderror" name="resultado" id="resultado" required @error('resultado') aria-invalid="true" aria-describedby="resultado-error" @enderror><option value="">Selecciona una resolución</option><option value="aprobada" @selected(old('resultado') === 'aprobada')>Publicar</option><option value="en_correccion" @selected(old('resultado') === 'en_correccion')>Devolver para corrección</option><option value="rechazada" @selected(old('resultado') === 'rechazada')>Rechazar</option></select>@error('resultado')<p class="invalid-feedback" id="resultado-error">{{ $message }}</p>@enderror</div>
                    <x-campo name="cupo_validado" label="Cupo validado de alumnos" type="number" :value="$ultimaRevision->instantanea_contenido->proyecto->cupo_maximo_alumnos ?? ''" min="1" max="2147483647" inputmode="numeric" help="Obligatorio al publicar. Debe coincidir con el cupo propuesto en esta revisión; si requiere cambios, devuelve para corrección." />
                    <x-campo name="motivo" label="Motivo y observaciones" type="textarea" required maxlength="1000" placeholder="Ej. Falta precisar el alcance: indiquen si incluye la app móvil." help="La empresa podrá consultar estas observaciones en el historial." />
                    <button class="btn btn-primary w-100" type="submit">Guardar resolución</button>
                </form>
            </section></div>
        </div>
    @else
        <section class="surface" aria-labelledby="contenido-titulo"><h2 id="contenido-titulo" class="section-heading">{{ $ultimaRevision ? 'Última versión enviada' : 'Borrador sin enviar' }}</h2><p class="field-hint">Este proyecto no tiene una revisión pendiente que se pueda resolver.</p><x-contenido-proyecto :contenido="$ultimaRevision ? $ultimaRevision->instantanea_contenido->proyecto : $proyecto" :habilidades="$ultimaRevision ? ($ultimaRevision->instantanea_contenido->habilidades ?? []) : $proyecto->habilidades" /></section>
    @endif
    @include('proyectos._historial')
</section>
@endsection
