<?php

namespace App\Http\Requests\Perfiles;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;

class FiltrarCatalogoRequest extends FormRequest
{
    public function authorize(): bool
    {
        return Gate::allows('consultar-catalogo');
    }

    public function rules(): array
    {
        return [
            'buscar' => ['nullable', 'string', 'max:150'],
            'empresa_id' => ['nullable', 'integer', 'not_in:0'],
            'modalidad' => ['nullable', 'string', 'max:250'],
            'habilidad_id' => ['nullable', 'integer', 'not_in:0'],
            'tipo_habilidad' => ['nullable', 'string', Rule::in(['dura', 'blanda'])],
            'page' => ['nullable', 'integer', 'min:1', 'max:10000'],
        ];
    }

    public function messages(): array
    {
        return [
            'string' => 'El filtro :attribute debe ser texto.',
            'integer' => 'Revisa el filtro :attribute.',
            'max' => 'El filtro :attribute supera el límite de :max.',
            'tipo_habilidad.in' => 'Selecciona una habilidad dura o blanda.',
        ];
    }

    public function attributes(): array
    {
        return ['buscar' => 'búsqueda', 'empresa_id' => 'empresa', 'modalidad' => 'modalidad',
            'habilidad_id' => 'habilidad', 'tipo_habilidad' => 'tipo de habilidad', 'page' => 'página'];
    }
}
