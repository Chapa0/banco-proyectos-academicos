<?php

namespace App\Http\Requests;

use Closure;
use Illuminate\Foundation\Http\FormRequest;

class CambiarClaveRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    public function rules(): array
    {
        return [
            'current_password' => ['required', 'string', 'max:1024'],
            'password' => ['required', 'string', 'min:12', 'confirmed', function (string $attribute, mixed $value, Closure $fail): void {
                if (is_string($value) && strlen($value) > 72) {
                    $fail('La contraseña debe ocupar como máximo 72 bytes; reduce su longitud.');
                }
            }],
        ];
    }

    public function messages(): array
    {
        return ['current_password.required' => 'Escribe tu contraseña actual.', 'password.required' => 'Escribe la nueva contraseña.',
            'password.min' => 'Usa al menos 12 caracteres.', 'password.confirmed' => 'La confirmación no coincide.'];
    }
}
