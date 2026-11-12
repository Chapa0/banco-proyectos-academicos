<?php

namespace App\Http\Requests\Proyectos;

use Illuminate\Foundation\Http\FormRequest;

abstract class PublicacionRequest extends FormRequest
{
    protected function normalizarTextos(array $campos): void
    {
        $valores = [];
        foreach ($campos as $campo) {
            $valor = $this->input($campo);
            if (is_string($valor)) {
                $valores[$campo] = trim($valor);
            }
        }
        $this->merge($valores);
    }

    protected function reglaVersion(): array
    {
        return ['required', 'string', 'regex:/\A[a-f0-9]{64}\z/'];
    }

    protected function camposProtegidos(): array
    {
        return array_fill_keys([
            'actor', 'actor_usuario_id', 'empresa_id', 'autor_usuario_id',
            'administrador_usuario_id', 'estado', 'revision_publicada_id',
        ], ['prohibited']);
    }

    public function messages(): array
    {
        return [
            'required' => 'El campo :attribute es obligatorio.',
            'required_if' => 'El campo :attribute es obligatorio para esta operación.',
            'string' => 'El campo :attribute debe ser texto.',
            'array' => 'Revisa la selección de :attribute.',
            'integer' => 'El campo :attribute debe ser un número entero.',
            'min' => 'El campo :attribute debe ser al menos :min.',
            'max' => 'El campo :attribute supera el límite de :max.',
            'distinct' => 'No repitas una habilidad en la selección.',
            'prohibited' => 'El campo :attribute no puede modificarse desde este formulario.',
            'date_format' => 'Indica una fecha válida con formato año-mes-día.',
            'version.required' => 'Recarga la página y revisa los datos antes de continuar.',
            'version.string' => 'Recarga la página y revisa los datos antes de continuar.',
            'version.regex' => 'Recarga la página y revisa los datos antes de continuar.',
            'resultado.in' => 'Selecciona aprobar, devolver para corrección o rechazar.',
            'contacto_correo.email' => 'Indica un correo de contacto válido.',
        ];
    }

    public function attributes(): array
    {
        return [
            'titulo' => 'título', 'descripcion' => 'descripción', 'problematica' => 'problemática',
            'objetivos' => 'objetivos', 'justificacion' => 'justificación', 'alcance' => 'alcance',
            'requisitos_academicos' => 'requisitos académicos', 'duracion_estimada' => 'duración estimada',
            'modalidad' => 'modalidad', 'fecha_inicio_estimada' => 'fecha estimada de inicio',
            'fecha_fin_estimada' => 'fecha estimada de fin', 'recursos' => 'recursos',
            'cupo_maximo_alumnos' => 'cupo máximo de alumnos', 'cupo_validado' => 'cupo validado',
            'habilidades_seleccionadas' => 'habilidades', 'habilidades_seleccionadas.*' => 'habilidad',
            'niveles' => 'niveles', 'niveles.*' => 'nivel mínimo', 'obligatorias' => 'habilidades obligatorias',
            'obligatorias.*' => 'habilidad obligatoria', 'version' => 'versión', 'revision_id' => 'revisión',
            'razon_social' => 'razón social', 'sector' => 'sector', 'identificacion' => 'identificación',
            'contacto_nombre' => 'nombre de contacto', 'contacto_correo' => 'correo de contacto',
            'contacto_telefono' => 'teléfono de contacto', 'motivo' => 'motivo', 'resultado' => 'resolución',
        ];
    }
}
