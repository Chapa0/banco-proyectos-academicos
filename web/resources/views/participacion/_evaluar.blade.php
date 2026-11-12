<form method="POST" action="{{ route('participacion.operar', ['tipo' => $tipo, 'solicitud' => $detalle->solicitud->id, 'accion' => 'evaluar']) }}" data-submit-label="Guardando evaluación…">
    @csrf
    @include('participacion._version', ['version' => $detalle->version])
    <p class="field-hint">Cada criterio usa la misma escala. Los comentarios explican la valoración; la puntuación no asigna automáticamente al alumno.</p>
    @foreach(['tecnico' => 'Conocimientos técnicos', 'blando' => 'Habilidades blandas', 'academico' => 'Requisitos académicos'] as $codigo => $nombre)
        @php
            $clave = 'puntuaciones.'.$codigo;
            $puntuacion = old($clave.'.puntuacion', '');
            $comentario = old($clave.'.comentario', '');
        @endphp
        <fieldset class="form-section">
            <legend class="h6">{{ $nombre }}</legend>
            <div class="mb-4"><div class="label-row"><label class="form-label" for="puntuacion-{{ $codigo }}">Valoración<span class="required-mark" aria-hidden="true">*</span></label><x-info :tema="$nombre" texto="0: no cumple lo que pide el proyecto. 1: cumple solo una parte. 2: cumple completamente." /></div><select class="form-select @error($clave.'.puntuacion') is-invalid @enderror" id="puntuacion-{{ $codigo }}" name="puntuaciones[{{ $codigo }}][puntuacion]" required @error($clave.'.puntuacion') aria-invalid="true" aria-describedby="puntuacion-{{ $codigo }}-error" @enderror><option value="">Selecciona una valoración</option>@foreach([0 => '0 · No cumple', 1 => '1 · Cumple parcialmente', 2 => '2 · Cumple'] as $valor => $etiqueta)<option value="{{ $valor }}" @selected(is_scalar($puntuacion) && (string) $puntuacion === (string) $valor)>{{ $etiqueta }}</option>@endforeach</select>@error($clave.'.puntuacion')<p class="invalid-feedback" id="puntuacion-{{ $codigo }}-error">{{ $message }}</p>@enderror</div>
            <div class="mb-4"><label class="form-label" for="comentario-{{ $codigo }}">Comentario de {{ mb_strtolower($nombre) }}<span class="required-mark" aria-hidden="true">*</span></label><textarea class="form-control @error($clave.'.comentario') is-invalid @enderror" id="comentario-{{ $codigo }}" name="puntuaciones[{{ $codigo }}][comentario]" rows="3" maxlength="10000" required placeholder="Explica brevemente la valoración que elegiste." @error($clave.'.comentario') aria-invalid="true" aria-describedby="comentario-{{ $codigo }}-error" @enderror>{{ is_scalar($comentario) ? $comentario : '' }}</textarea>@error($clave.'.comentario')<p class="invalid-feedback" id="comentario-{{ $codigo }}-error">{{ $message }}</p>@enderror</div>
        </fieldset>
    @endforeach
    <x-campo name="comentarios" label="Comentario general" type="textarea" maxlength="10000" required placeholder="Ej. Buen perfil técnico; recomendamos una entrevista para confirmar disponibilidad de horario." info="Tu valoración global del candidato. La administración la consulta antes de autorizar una asignación." />
    <div class="mb-4"><label class="form-label" for="recomendada">¿Recomiendas al candidato?<span class="required-mark" aria-hidden="true">*</span></label><select class="form-select @error('recomendada') is-invalid @enderror" id="recomendada" name="recomendada" required @error('recomendada') aria-invalid="true" aria-describedby="recomendada-error" @enderror><option value="">Selecciona una respuesta</option><option value="1" @selected(is_scalar(old('recomendada')) && (string) old('recomendada') === '1')>Sí</option><option value="0" @selected(is_scalar(old('recomendada')) && (string) old('recomendada') === '0')>No</option></select>@error('recomendada')<p class="invalid-feedback" id="recomendada-error">{{ $message }}</p>@enderror</div>
    <p class="field-hint">Guardar una nueva evaluación conserva la anterior e invalida una preselección previa. Después podrás preseleccionar expresamente al candidato si lo recomiendas.</p>
    <button class="btn btn-primary" type="submit">Guardar evaluación</button>
</form>
