<?php

namespace App\Http\Requests\Proyectos;

use Illuminate\Support\Facades\Gate;

class EnviarProyectoRequest extends PublicacionRequest
{
    public function authorize(): bool
    {
        return Gate::allows('gestionar-proyectos');
    }

    public function rules(): array
    {
        return array_merge(['version' => $this->reglaVersion()], $this->camposProtegidos());
    }
}
