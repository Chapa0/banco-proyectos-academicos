<?php

namespace App\Http\Requests\Participacion;

use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;

class OperarParticipacionRequest extends ParticipacionRequest
{
    public function authorize(): bool
    {
        $accion = $this->route('accion');
        if ($this->routeIs('seguimiento.operar')) {
            return Gate::allows('gestionar-ciclo') && in_array($accion, [
                'iniciar', 'reanudar', 'finalizar', 'cancelar', 'retirar_alumno', 'retirar_director',
            ], true);
        }
        if (! Gate::allows('consultar-participacion')) {
            return false;
        }
        $rol = $this->user()?->rol_principal;
        $tipo = $this->route('tipo');

        return match ($accion) {
            'cancelar' => ($rol === 'alumno' && $tipo === 'candidatura') || ($rol === 'profesor' && $tipo === 'direccion'),
            'evaluar', 'preseleccionar' => $rol === 'empresa' && $tipo === 'candidatura',
            'aprobar', 'rechazar' => $rol === 'administrador' && in_array($tipo, ['candidatura', 'direccion'], true),
            default => false,
        };
    }

    protected function prepareForValidation(): void
    {
        $valores = [];
        foreach (['motivo', 'comentarios', 'puntuaciones'] as $campo) {
            if ($this->exists($campo)) {
                $valores[$campo] = $this->normalizarTexto($this->input($campo));
            }
        }
        $this->merge($valores);
    }

    public function rules(): array
    {
        $reglas = array_merge($this->camposProtegidos(), [
            'version' => $this->reglaVersion(),
            'experiencia_aplicable' => ['prohibited'], 'justificacion' => ['prohibited'],
            'motivo' => ['prohibited'], 'asignacion_id' => ['prohibited'],
            'puntuaciones' => ['prohibited'], 'comentarios' => ['prohibited'], 'recomendada' => ['prohibited'],
        ]);
        $accion = $this->route('accion');
        $ciclo = $this->routeIs('seguimiento.operar');
        if (($ciclo && in_array($accion, ['finalizar', 'cancelar', 'retirar_alumno', 'retirar_director'], true))
            || (! $ciclo && in_array($accion, ['aprobar', 'rechazar'], true))) {
            $reglas['motivo'] = ['required', 'string', 'max:1000'];
        }
        if ($ciclo && in_array($accion, ['retirar_alumno', 'retirar_director'], true)) {
            $reglas['asignacion_id'] = ['required', 'integer', 'regex:/\A-?[0-9]+\z/', 'not_in:0'];
        }
        if (! $ciclo && $accion === 'evaluar') {
            $reglas['comentarios'] = ['required', 'string', 'max:10000'];
            $reglas['recomendada'] = ['required', 'boolean'];
            $reglas['puntuaciones'] = ['required', 'array:tecnico,blando,academico', 'required_array_keys:tecnico,blando,academico'];
            foreach (['tecnico', 'blando', 'academico'] as $codigo) {
                $reglas['puntuaciones.'.$codigo] = ['required', 'array:puntuacion,comentario', 'required_array_keys:puntuacion,comentario'];
                $reglas['puntuaciones.'.$codigo.'.puntuacion'] = ['required', 'integer', 'regex:/\A[012]\z/', Rule::in([0, 1, 2])];
                $reglas['puntuaciones.'.$codigo.'.comentario'] = ['required', 'string', 'max:10000'];
            }
        }

        return $reglas;
    }

    public function datos(): array
    {
        $accion = $this->route('accion');
        $ciclo = $this->routeIs('seguimiento.operar');
        $campos = match (true) {
            ! $ciclo && $accion === 'evaluar' => ['puntuaciones', 'comentarios', 'recomendada'],
            $ciclo && in_array($accion, ['retirar_alumno', 'retirar_director'], true) => ['asignacion_id', 'motivo'],
            ($ciclo && in_array($accion, ['finalizar', 'cancelar'], true))
                || (! $ciclo && in_array($accion, ['aprobar', 'rechazar'], true)) => ['motivo'],
            default => [],
        };
        $datos = $this->safe()->only($campos);
        if ($accion === 'evaluar' && ! $ciclo) {
            $datos['recomendada'] = (bool) $datos['recomendada'];
            foreach (['tecnico', 'blando', 'academico'] as $codigo) {
                $datos['puntuaciones'][$codigo]['puntuacion'] = (int) $datos['puntuaciones'][$codigo]['puntuacion'];
            }
        }
        if (isset($datos['asignacion_id'])) {
            $datos['asignacion_id'] = (int) $datos['asignacion_id'];
        }

        return $datos;
    }
}
