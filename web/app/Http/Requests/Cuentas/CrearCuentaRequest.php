<?php

namespace App\Http\Requests\Cuentas;

use Illuminate\Validation\Rule;

class CrearCuentaRequest extends CuentaRequest
{
    protected function prepareForValidation(): void
    {
        $this->normalizarIdentidad();
    }

    public function rules(): array
    {
        return [
            'nombre' => ['required', 'string', 'max:150'],
            'correo' => ['required', 'string', 'email:rfc', 'max:254'],
            'rol' => ['required', Rule::in(['administrador', 'empresa', 'alumno', 'profesor'])],
            'razon_social' => ['nullable', 'required_if:rol,empresa', 'string', 'max:250'],
            'password' => $this->reglasClave(),
        ];
    }
}
