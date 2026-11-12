<?php

namespace App\Http\Requests\Consultas;

use App\Services\ConsultaService;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;

class FiltrarAvisosRequest extends FormRequest
{
    public function authorize(): bool
    {
        return Gate::allows('consultar-avisos');
    }

    public function rules(): array
    {
        return [
            'estado' => ['nullable', 'string', Rule::in(array_keys(ConsultaService::ESTADOS_AVISO))],
            'buscar' => ['nullable', 'string', 'max:150'],
            'page' => ['nullable', 'integer', 'regex:/\A[1-9][0-9]*\z/', 'min:1', 'max:10000'],
            'actor' => ['prohibited'], 'actor_usuario_id' => ['prohibited'],
            'usuario_id' => ['prohibited'], 'destinatario_usuario_id' => ['prohibited'],
        ];
    }

    public function messages(): array
    {
        return [
            'string' => 'El filtro :attribute debe ser texto.',
            'in' => 'Selecciona una opción válida para :attribute.',
            'integer' => 'El filtro :attribute debe ser un número entero.',
            'regex' => 'Revisa el filtro :attribute.',
            'max' => 'El filtro :attribute supera el límite de :max.',
            'min' => 'El filtro :attribute debe ser al menos :min.',
            'prohibited' => 'El campo :attribute no está permitido en esta consulta.',
        ];
    }

    public function attributes(): array
    {
        return ['estado' => 'lectura', 'buscar' => 'búsqueda', 'page' => 'página'];
    }
}
