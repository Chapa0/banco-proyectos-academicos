<?php

namespace App\Http\Requests\Proyectos;

use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Validator;

class GuardarProyectoRequest extends PublicacionRequest
{
    private const CAMPOS = [
        'titulo', 'descripcion', 'problematica', 'objetivos', 'justificacion', 'alcance',
        'requisitos_academicos', 'duracion_estimada', 'modalidad', 'fecha_inicio_estimada',
        'fecha_fin_estimada', 'recursos', 'cupo_maximo_alumnos',
    ];

    public function authorize(): bool
    {
        return Gate::allows('gestionar-proyectos');
    }

    protected function prepareForValidation(): void
    {
        $this->normalizarTextos(self::CAMPOS);
    }

    public function rules(): array
    {
        $reglas = [
            'titulo' => ['required', 'string', 'max:250'],
            'descripcion' => ['nullable', 'string', 'max:10000'],
            'problematica' => ['nullable', 'string', 'max:10000'],
            'objetivos' => ['nullable', 'string', 'max:10000'],
            'justificacion' => ['nullable', 'string', 'max:10000'],
            'alcance' => ['nullable', 'string', 'max:10000'],
            'requisitos_academicos' => ['nullable', 'string', 'max:10000'],
            'duracion_estimada' => ['nullable', 'string', 'max:250'],
            'modalidad' => ['nullable', 'string', 'max:250'],
            'fecha_inicio_estimada' => ['nullable', 'date_format:Y-m-d'],
            'fecha_fin_estimada' => ['nullable', 'date_format:Y-m-d'],
            'recursos' => ['nullable', 'string', 'max:10000'],
            'cupo_maximo_alumnos' => ['nullable', 'integer', 'min:1', 'max:2147483647'],
            'habilidades_seleccionadas' => ['nullable', 'array', 'max:200'],
            'habilidades_seleccionadas.*' => ['required', 'integer', 'not_in:0', 'distinct'],
            'niveles' => ['nullable', 'array', 'max:200'],
            'niveles.*' => ['nullable', 'string', 'max:250'],
            'obligatorias' => ['nullable', 'array', 'max:200'],
            'obligatorias.*' => ['required', 'integer', 'not_in:0', 'distinct'],
            'habilidades' => ['prohibited'],
            'version' => $this->isMethod('PUT') ? $this->reglaVersion() : ['prohibited'],
        ];

        return array_merge($reglas, $this->camposProtegidos());
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            if ($validator->errors()->has('fecha_inicio_estimada') || $validator->errors()->has('fecha_fin_estimada')) {
                return;
            }
            $inicio = $this->input('fecha_inicio_estimada');
            $fin = $this->input('fecha_fin_estimada');
            if (is_string($inicio) && is_string($fin) && $inicio !== '' && $fin !== '' && $fin < $inicio) {
                $validator->errors()->add('fecha_fin_estimada', 'La fecha estimada de fin debe ser igual o posterior al inicio.');
            }
        });
    }

    public function datos(): array
    {
        $validados = $this->validated();
        $datos = [];
        foreach (self::CAMPOS as $campo) {
            $datos[$campo] = $validados[$campo] ?? null;
        }
        $datos['cupo_maximo_alumnos'] = isset($datos['cupo_maximo_alumnos']) ? (int) $datos['cupo_maximo_alumnos'] : null;
        $obligatorias = array_map('intval', $validados['obligatorias'] ?? []);
        $datos['habilidades'] = [];
        foreach ($validados['habilidades_seleccionadas'] ?? [] as $id) {
            $nivel = $validados['niveles'][$id] ?? null;
            $datos['habilidades'][] = [
                'habilidad_id' => (int) $id,
                'nivel_minimo' => is_string($nivel) && trim($nivel) !== '' ? trim($nivel) : null,
                'obligatoria' => in_array((int) $id, $obligatorias, true),
            ];
        }

        return $datos;
    }
}
