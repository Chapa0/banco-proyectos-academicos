<fieldset class="form-section">
    <legend>Habilidades</legend>
    <p class="field-hint" id="habilidades-ayuda">Selecciona las habilidades que quieres conservar en tu perfil. Puedes completar su nivel, descripción y evidencia. Al desmarcar una habilidad, se quitará de tu perfil al guardar.</p>
    @php
        $iniciales = session()->hasOldInput() ? [] : array_map(fn ($h) => (string) $h->habilidad_id, $habilidadesPerfil);
        $seleccionadas = old('habilidades_seleccionadas', $iniciales);
        $seleccionadas = is_array($seleccionadas) ? array_filter($seleccionadas, 'is_scalar') : [];
    @endphp
    @forelse($habilidades as $habilidad)
        @php
            $inicial = collect($habilidadesPerfil)->firstWhere('habilidad_id', $habilidad->id);
            $ampliar = in_array((string) $habilidad->id, $seleccionadas, false)
                || $errors->has('niveles.'.$habilidad->id)
                || $errors->has('descripciones.'.$habilidad->id)
                || $errors->has('evidencias.'.$habilidad->id);
        @endphp
        <section class="profile-skill" aria-labelledby="habilidad-etiqueta-{{ $habilidad->id }}">
            <div class="form-check skill-selection">
                <input class="form-check-input" type="checkbox" name="habilidades_seleccionadas[]" value="{{ $habilidad->id }}" id="habilidad-{{ $habilidad->id }}" @checked(in_array((string) $habilidad->id, $seleccionadas, false)) aria-describedby="habilidades-ayuda">
                <label class="form-check-label fw-semibold" id="habilidad-etiqueta-{{ $habilidad->id }}" for="habilidad-{{ $habilidad->id }}">{{ $habilidad->nombre }}<span class="field-hint fw-normal">{{ $habilidad->tipo === 'dura' ? 'Habilidad dura' : 'Habilidad blanda' }}</span></label>
            </div>
            <details class="profile-skill-details" @if($ampliar) open @endif>
            <summary>Nivel, descripción y evidencia<span class="visually-hidden"> de {{ $habilidad->nombre }}</span></summary>
            @foreach(['niveles' => ['Nivel de dominio', 'text', 250, $inicial?->nivel_dominio ?? '', 'Por ejemplo, básico o intermedio.', 'Ej. Intermedio'], 'descripciones' => ['Descripción', 'textarea', 10000, $inicial?->descripcion ?? '', 'Describe cómo aplicas esta habilidad.', $habilidad->tipo === 'dura' ? 'Ej. Diseñé el modelo de datos de un sistema escolar en un proyecto de clase.' : 'Ej. Coordiné al equipo y expuse los avances del proyecto final ante el grupo.'], 'evidencias' => ['Evidencia', 'textarea', 10000, $inicial?->evidencia ?? '', 'Escribe una descripción o un enlace a tu evidencia.', $habilidad->tipo === 'dura' ? 'Ej. Repositorio github.com/usuario/proyecto o constancia del curso.' : 'Ej. Constancia de participación o carta de un profesor.']] as $grupo => [$etiqueta, $tipo, $limite, $valorInicial, $ayuda, $ejemplo])
                @php
                    $clave = $grupo.'.'.$habilidad->id;
                    $idCampo = $grupo.'-'.$habilidad->id;
                    $anterior = old($clave, $valorInicial);
                    $valor = is_scalar($anterior) ? (string) $anterior : '';
                @endphp
                <div class="mb-3">
                    <label class="form-label" for="{{ $idCampo }}">{{ $etiqueta }}<span class="visually-hidden"> de {{ $habilidad->nombre }}</span></label>
                    @if($tipo === 'textarea')
                        <textarea id="{{ $idCampo }}" name="{{ $grupo }}[{{ $habilidad->id }}]" rows="3" maxlength="{{ $limite }}" placeholder="{{ $ejemplo }}" class="form-control @error($clave) is-invalid @enderror" aria-describedby="{{ $idCampo }}-ayuda @error($clave) {{ $idCampo }}-error @enderror" @error($clave) aria-invalid="true" @enderror>{{ $valor }}</textarea>
                    @else
                        <input id="{{ $idCampo }}" name="{{ $grupo }}[{{ $habilidad->id }}]" type="text" value="{{ $valor }}" maxlength="{{ $limite }}" placeholder="{{ $ejemplo }}" class="form-control @error($clave) is-invalid @enderror" aria-describedby="{{ $idCampo }}-ayuda @error($clave) {{ $idCampo }}-error @enderror" @error($clave) aria-invalid="true" @enderror>
                    @endif
                    <p class="form-text" id="{{ $idCampo }}-ayuda">{{ $ayuda }}</p>
                    @error($clave)<p class="invalid-feedback" id="{{ $idCampo }}-error">{{ $message }}</p>@enderror
                </div>
            @endforeach
            </details>
        </section>
    @empty
        <p class="text-body-secondary mb-0">Todavía no hay habilidades en el catálogo. Puedes guardar los demás datos de tu perfil.</p>
    @endforelse
</fieldset>
