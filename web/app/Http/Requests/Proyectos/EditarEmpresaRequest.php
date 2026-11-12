<?php

namespace App\Http\Requests\Proyectos;

use Illuminate\Support\Facades\Gate;

class EditarEmpresaRequest extends PublicacionRequest
{
    public function authorize(): bool
    {
        return Gate::allows('gestionar-proyectos');
    }

    protected function prepareForValidation(): void
    {
        $this->normalizarTextos([
            'razon_social', 'sector', 'identificacion', 'contacto_nombre', 'contacto_correo', 'contacto_telefono',
        ]);
        if (is_string($this->input('contacto_correo'))) {
            $this->merge(['contacto_correo' => mb_strtolower($this->input('contacto_correo'))]);
        }
    }

    public function rules(): array
    {
        return array_merge([
            'version' => $this->reglaVersion(),
            'razon_social' => ['required', 'string', 'max:250'],
            'sector' => ['nullable', 'string', 'max:250'],
            'identificacion' => ['nullable', 'string', 'max:100'],
            'contacto_nombre' => ['nullable', 'string', 'max:150'],
            'contacto_correo' => ['nullable', 'string', 'email:rfc', 'max:254'],
            'contacto_telefono' => ['nullable', 'string', 'max:50'],
        ], $this->camposProtegidos());
    }

    public function datos(): array
    {
        $validados = $this->validated();
        $datos = [];
        foreach (['razon_social', 'sector', 'identificacion', 'contacto_nombre', 'contacto_correo', 'contacto_telefono'] as $campo) {
            $datos[$campo] = $validados[$campo] ?? null;
        }

        return $datos;
    }
}
