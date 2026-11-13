<?php

namespace App\Http\Requests\Cuentas;

use App\Services\HabilidadService;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;

class GuardarHabilidadRequest extends FormRequest
{
    public function authorize(): bool
    {
        return Gate::allows('administrar-cuentas');
    }

    public function rules(): array
    {
        return [
            'nombre' => ['required', 'string', 'max:100', 'regex:/\S/u'],
            'tipo' => ['required', Rule::in(array_keys(HabilidadService::TIPOS))],
            'descripcion' => ['nullable', 'string', 'max:500'],
            'habilidad_id' => ['nullable', 'integer'],
        ];
    }

    public function messages(): array
    {
        return [
            'nombre.required' => 'Escribe el nombre de la habilidad.',
            'nombre.regex' => 'Escribe el nombre de la habilidad.',
            'nombre.max' => 'El nombre admite hasta 100 caracteres.',
            'tipo.required' => 'Elige si es una habilidad dura o blanda.',
            'tipo.in' => 'Elige si es una habilidad dura o blanda.',
            'descripcion.max' => 'La descripción admite hasta 500 caracteres.',
        ];
    }
}
