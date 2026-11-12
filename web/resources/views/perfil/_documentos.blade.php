@php
    $docs = collect($documentos ?? []);
    $cv = $docs->firstWhere('tipo', 'curriculum');
    $evidencias = $docs->where('tipo', 'evidencia')->groupBy('habilidad_id');
    $formularioActivo = old('tipo');
    $nombresHabilidad = collect($habilidadesPerfil ?? [])->pluck('nombre', 'habilidad_id');
@endphp
<section class="surface mt-4" id="documentos" aria-labelledby="documentos-titulo">
    <h2 class="section-heading" id="documentos-titulo">Documentos PDF</h2>
    <p class="field-hint">Solo archivos PDF de máximo 5 MB. Los verán quienes ya pueden consultar tu perfil: la administración y las empresas de los proyectos a los que te postulas{{ $rol === 'alumno' ? ', y tu director cuando seas asignado' : '' }}.</p>

    <div class="document-block">
        <h3 class="h6">Currículum</h3>
        @if($cv)
            <div class="document-row">
                <x-documento-enlace :documento="$cv" />
                <form method="POST" action="{{ route('documentos.destroy', $cv->id) }}" data-confirm="¿Quitar tu currículum del perfil? Podrás subir otro cuando quieras.">@csrf @method('DELETE')<button class="btn btn-link text-danger px-2" type="submit">Quitar<span class="visually-hidden"> currículum</span></button></form>
            </div>
        @else
            <p class="text-body-secondary mb-2">Todavía no has subido tu currículum.</p>
        @endif
        <form class="document-upload" method="POST" action="{{ route('documentos.store') }}" enctype="multipart/form-data" data-submit-label="Subiendo…">
            @csrf
            <input type="hidden" name="tipo" value="curriculum">
            <div class="label-row"><label class="form-label" for="archivo-curriculum">{{ $cv ? 'Reemplazar currículum' : 'Subir currículum' }}</label><x-info tema="Currículum" texto="Un solo PDF con tu experiencia, formación y datos de contacto. Si subes otro, reemplaza al actual." /></div>
            <div class="document-upload-row">
                <input class="form-control @if($formularioActivo === 'curriculum' && $errors->has('archivo')) is-invalid @endif" type="file" id="archivo-curriculum" name="archivo" accept="application/pdf,.pdf" required aria-describedby="archivo-curriculum-ayuda @if($formularioActivo === 'curriculum' && $errors->has('archivo')) archivo-curriculum-error @endif">
                <button class="btn btn-outline-secondary" type="submit">{{ $cv ? 'Reemplazar' : 'Subir' }}</button>
            </div>
            <p class="form-text field-hint" id="archivo-curriculum-ayuda">PDF de máximo 5 MB.</p>
            @if($formularioActivo === 'curriculum' && $errors->has('archivo'))<p class="invalid-feedback d-block" id="archivo-curriculum-error">{{ $errors->first('archivo') }}</p>@endif
        </form>
    </div>

    @if($rol === 'alumno')
        <div class="document-block">
            <h3 class="h6">Evidencias de habilidades</h3>
            @if($nombresHabilidad->isEmpty())
                <p class="text-body-secondary mb-0">Primero selecciona y guarda al menos una habilidad en tu perfil; después podrás adjuntar sus constancias.</p>
            @else
                @foreach($nombresHabilidad as $habilidadId => $nombre)
                    @if($evidencias->has($habilidadId))
                        <p class="fw-semibold mb-1 mt-3">{{ $nombre }}</p>
                        @foreach($evidencias[$habilidadId] as $evidencia)
                            <div class="document-row">
                                <x-documento-enlace :documento="$evidencia" />
                                <form method="POST" action="{{ route('documentos.destroy', $evidencia->id) }}" data-confirm="¿Quitar este archivo de la habilidad?">@csrf @method('DELETE')<button class="btn btn-link text-danger px-2" type="submit">Quitar<span class="visually-hidden"> {{ $evidencia->nombre_original }}</span></button></form>
                            </div>
                        @endforeach
                    @endif
                @endforeach
                <form class="document-upload mt-3" method="POST" action="{{ route('documentos.store') }}" enctype="multipart/form-data" data-submit-label="Subiendo…">
                    @csrf
                    <input type="hidden" name="tipo" value="evidencia">
                    <div class="row g-3">
                        <div class="col-md-5">
                            <label class="form-label" for="evidencia-habilidad">Habilidad</label>
                            <select class="form-select @if($formularioActivo === 'evidencia' && $errors->has('habilidad_id')) is-invalid @endif" id="evidencia-habilidad" name="habilidad_id" required>
                                <option value="">Selecciona una habilidad</option>
                                @foreach($nombresHabilidad as $habilidadId => $nombre)<option value="{{ $habilidadId }}" @selected((string) old('habilidad_id') === (string) $habilidadId)>{{ $nombre }}</option>@endforeach
                            </select>
                            @if($formularioActivo === 'evidencia' && $errors->has('habilidad_id'))<p class="invalid-feedback d-block">{{ $errors->first('habilidad_id') }}</p>@endif
                        </div>
                        <div class="col-md-7">
                            <div class="label-row"><label class="form-label" for="archivo-evidencia">Constancia o certificado</label><x-info tema="Evidencia" texto="Por ejemplo, un certificado de curso, una constancia de participación o un reporte de proyecto. Hasta tres PDF por habilidad." /></div>
                            <div class="document-upload-row">
                                <input class="form-control @if($formularioActivo === 'evidencia' && $errors->has('archivo')) is-invalid @endif" type="file" id="archivo-evidencia" name="archivo" accept="application/pdf,.pdf" required aria-describedby="archivo-evidencia-ayuda @if($formularioActivo === 'evidencia' && $errors->has('archivo')) archivo-evidencia-error @endif">
                                <button class="btn btn-outline-secondary" type="submit">Subir</button>
                            </div>
                            <p class="form-text field-hint" id="archivo-evidencia-ayuda">PDF de máximo 5 MB; hasta tres por habilidad.</p>
                            @if($formularioActivo === 'evidencia' && $errors->has('archivo'))<p class="invalid-feedback d-block" id="archivo-evidencia-error">{{ $errors->first('archivo') }}</p>@endif
                        </div>
                    </div>
                </form>
            @endif
        </div>
    @endif
</section>
