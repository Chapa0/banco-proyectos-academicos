<?php

namespace App\Http\Requests\Proyectos;

use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;

class ResolverProyectoRequest extends PublicacionRequest
{
    public function authorize(): bool
    {
        return Gate::allows('revisar-proyectos');
    }

    protected function prepareForValidation(): void
    {
        $this->normalizarTextos(['motivo']);
    }

    public function rules(): array
    {
        return array_merge([
            'version' => $this->reglaVersion(),
            'revision_id' => ['required', 'integer', 'not_in:0'],
            'resultado' => ['required', 'string', Rule::in(['aprobada', 'en_correccion', 'rechazada'])],
            'motivo' => ['required', 'string', 'max:1000'],
            'cupo_validado' => ['exclude_unless:resultado,aprobada', 'required', 'integer', 'min:1', 'max:2147483647'],
        ], $this->camposProtegidos());
    }
}
