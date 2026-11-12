<?php

namespace App\Http\Requests\Cuentas;

use Illuminate\Validation\Rule;

class EstadoCuentaRequest extends CuentaRequest
{
    protected function prepareForValidation(): void
    {
        $this->normalizarIdentidad();
    }

    public function rules(): array
    {
        return [
            'estado' => ['required', Rule::in(['activa', 'inactiva'])],
            'motivo' => ['required', 'string', 'max:1000'],
            'version_acceso' => ['required', 'integer', 'min:1'],
        ];
    }
}
