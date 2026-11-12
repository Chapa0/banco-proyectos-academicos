<?php

namespace App\Http\Requests\Consultas;

use App\Services\ConsultaService;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;

class FiltrarReporteRequest extends FormRequest
{
    public function authorize(): bool
    {
        return Gate::allows('consultar-reportes');
    }

    public function rules(): array
    {
        $tipo = $this->route('tipo') ?? 'proyectos';
        $consulta = app(ConsultaService::class);
        $estados = $consulta->estadosReporte($tipo);
        $reglas = [
            'buscar' => ['nullable', 'string', 'max:150'],
            'page' => ['nullable', 'integer', 'regex:/\A[1-9][0-9]*\z/', 'min:1', 'max:10000'],
            'estado' => $estados === [] ? ['prohibited'] : ['nullable', 'string', Rule::in(array_keys($estados))],
            'empresa_id' => ['prohibited'], 'proyecto_id' => ['prohibited'], 'profesor_id' => ['prohibited'],
            'actor' => ['prohibited'], 'actor_usuario_id' => ['prohibited'],
            'usuario_id' => ['prohibited'], 'destinatario_usuario_id' => ['prohibited'],
        ];
        foreach (ConsultaService::FILTROS_REPORTE[$tipo] as $campo) {
            $reglas[$campo] = ['nullable', 'integer', 'regex:/\A-?[1-9][0-9]*\z/'];
        }

        return $reglas;
    }

    public function messages(): array
    {
        return [
            'string' => 'El filtro :attribute debe ser texto.',
            'in' => 'Selecciona una opción válida para :attribute.',
            'integer' => 'El filtro :attribute debe ser un número entero.',
            'regex' => 'Revisa el filtro :attribute.',
            'max' => 'El filtro :attribute supera el límite de :max.',
            'min' => 'El filtro :attribute debe ser al menos :min.',
            'prohibited' => 'El filtro :attribute no está disponible en este reporte.',
        ];
    }

    public function attributes(): array
    {
        return ['buscar' => 'búsqueda', 'estado' => 'estado', 'page' => 'página',
            'empresa_id' => 'empresa', 'proyecto_id' => 'proyecto', 'profesor_id' => 'profesor'];
    }
}
