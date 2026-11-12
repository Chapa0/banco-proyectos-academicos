<?php

namespace App\Http\Requests\Cuentas;

class RelevarRepresentanteRequest extends CuentaRequest
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
            'password' => $this->reglasClave(),
            'motivo' => ['required', 'string', 'max:1000'],
        ];
    }
}
