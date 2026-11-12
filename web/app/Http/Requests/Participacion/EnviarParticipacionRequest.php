<?php

namespace App\Http\Requests\Participacion;

use Illuminate\Support\Facades\Gate;

class EnviarParticipacionRequest extends ParticipacionRequest
{
    public function authorize(): bool
    {
        return Gate::allows('participar');
    }

    protected function prepareForValidation(): void
    {
        $this->merge([
            'experiencia_aplicable' => $this->normalizarTexto($this->input('experiencia_aplicable')),
            'justificacion' => $this->normalizarTexto($this->input('justificacion')),
        ]);
    }

    public function rules(): array
    {
        $texto = $this->user()?->rol_principal === 'profesor' ? ['required', 'string', 'max:10000'] : ['prohibited'];

        return array_merge($this->camposProtegidos(), [
            'version' => $this->reglaVersion(),
            'experiencia_aplicable' => $texto, 'justificacion' => $texto,
            'motivo' => ['prohibited'], 'puntuaciones' => ['prohibited'], 'comentarios' => ['prohibited'],
            'recomendada' => ['prohibited'], 'asignacion_id' => ['prohibited'],
        ]);
    }

    public function datos(): array
    {
        return $this->user()->rol_principal === 'profesor'
            ? $this->safe()->only(['experiencia_aplicable', 'justificacion']) : [];
    }
}
