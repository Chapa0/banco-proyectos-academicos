<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Str;

class LoginRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        $this->merge(['correo' => is_string($this->correo) ? Str::lower(trim($this->correo)) : $this->correo]);
    }

    public function rules(): array
    {
        return ['correo' => ['required', 'string', 'email:rfc', 'max:254'], 'password' => ['required', 'string', 'max:1024']];
    }

    public function messages(): array
    {
        return ['correo.required' => 'Escribe tu correo.', 'correo.email' => 'Escribe un correo válido.', 'password.required' => 'Escribe tu contraseña.'];
    }
}
