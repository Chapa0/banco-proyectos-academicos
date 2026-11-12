<?php

namespace App\Http\Requests\Cuentas;

use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Gate;

abstract class CuentaRequest extends FormRequest
{
    public function authorize(): bool
    {
        return Gate::allows('administrar-cuentas');
    }

    protected function normalizarIdentidad(): void
    {
        $values = [];
        foreach (['nombre', 'correo', 'razon_social', 'motivo'] as $field) {
            $value = $this->input($field);
            if (is_string($value)) {
                $values[$field] = $field === 'correo' ? mb_strtolower(trim($value)) : trim($value);
            }
        }
        $this->merge($values);
    }

    protected function reglasClave(): array
    {
        return ['required', 'string', 'min:12', 'confirmed', function (string $attribute, mixed $value, Closure $fail): void {
            if (is_string($value) && strlen($value) > 72) {
                $fail('La contraseña no puede superar 72 bytes; usa una frase de longitud menor.');
            }
        }];
    }

    public function attributes(): array
    {
        return [
            'nombre' => 'nombre', 'correo' => 'correo', 'rol' => 'rol',
            'razon_social' => 'razón social', 'password' => 'contraseña',
            'motivo' => 'motivo', 'version_acceso' => 'versión de la cuenta', 'estado' => 'estado',
        ];
    }

    public function messages(): array
    {
        return [
            'required' => 'El campo :attribute es obligatorio.',
            'string' => 'El campo :attribute debe ser texto.',
            'email' => 'Indica un correo válido.',
            'max' => 'El campo :attribute admite hasta :max caracteres.',
            'password.min' => 'La contraseña debe tener al menos 12 caracteres.',
            'password.confirmed' => 'La confirmación de contraseña no coincide.',
            'rol.in' => 'Selecciona uno de los cuatro roles.',
            'estado.in' => 'Selecciona un estado de cuenta válido.',
            'razon_social.required_if' => 'La cuenta de empresa requiere una razón social.',
            'version_acceso.required' => 'Recarga la página antes de modificar la cuenta.',
            'version_acceso.integer' => 'Recarga la página antes de modificar la cuenta.',
            'version_acceso.min' => 'Recarga la página antes de modificar la cuenta.',
        ];
    }
}
