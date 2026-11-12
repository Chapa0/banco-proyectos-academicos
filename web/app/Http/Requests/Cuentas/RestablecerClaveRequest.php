<?php

namespace App\Http\Requests\Cuentas;

class RestablecerClaveRequest extends CuentaRequest
{
    protected function prepareForValidation(): void
    {
        $this->normalizarIdentidad();
    }

    public function rules(): array
    {
        return [
            'password' => $this->reglasClave(),
            'motivo' => ['required', 'string', 'max:1000'],
            'version_acceso' => ['required', 'integer', 'min:1'],
        ];
    }
}
