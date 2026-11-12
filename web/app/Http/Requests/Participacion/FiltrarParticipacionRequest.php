<?php

namespace App\Http\Requests\Participacion;

use App\Services\ParticipacionService;
use App\Services\PublicacionService;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;

class FiltrarParticipacionRequest extends ParticipacionRequest
{
    public function authorize(): bool
    {
        return Gate::allows('consultar-participacion');
    }

    public function rules(): array
    {
        $estados = $this->routeIs('seguimiento.index') ? PublicacionService::ESTADOS
            : ($this->route('tipo') === 'candidatura' ? ParticipacionService::ESTADOS_CANDIDATURA : ParticipacionService::ESTADOS_DIRECCION);

        return [
            'buscar' => ['nullable', 'string', 'max:150'],
            'estado' => ['nullable', 'string', Rule::in(array_keys($estados))],
            'page' => ['nullable', 'integer', 'min:1', 'max:10000'],
        ];
    }
}
