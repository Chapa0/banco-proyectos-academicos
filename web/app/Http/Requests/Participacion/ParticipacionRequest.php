<?php

namespace App\Http\Requests\Participacion;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

abstract class ParticipacionRequest extends FormRequest
{
    protected function reglaVersion(): array
    {
        return ['required', 'string', 'regex:/\A[a-f0-9]{64}\z/'];
    }

    protected function camposProtegidos(): array
    {
        return array_fill_keys([
            'actor', 'actor_usuario_id', 'usuario_id', 'alumno_id', 'profesor_id',
            'solicitante_id', 'representante_id', 'representante_usuario_id', 'administrador_id',
            'administrador_usuario_id', 'evaluador_usuario_id', 'empresa_id', 'proyecto_id',
            'candidatura_id', 'solicitud_id', 'solicitud_direccion_id', 'id',
            'estado', 'estado_cuenta', 'rol', 'rol_principal', 'correo', 'hash_contrasena',
            'resultado', 'decision_id', 'evaluacion_id', 'evaluacion_vigente_id',
            'evento_preseleccion_id', 'revision_publicada_id', 'tipo', 'accion',
        ], ['prohibited']);
    }

    protected function normalizarTexto(mixed $valor): mixed
    {
        if (is_string($valor)) {
            return trim($valor);
        }
        if (is_array($valor)) {
            return array_map(fn ($elemento) => $this->normalizarTexto($elemento), $valor);
        }

        return $valor;
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            if ($this->allFiles() !== []) {
                $validator->errors()->add('archivos', 'Este formulario no admite cargar archivos.');
            }
        });
    }

    public function messages(): array
    {
        return [
            'required' => 'El campo :attribute es obligatorio.',
            'required_array_keys' => 'Completa los tres criterios de evaluación.',
            'string' => 'El campo :attribute debe ser texto.',
            'array' => 'Revisa la estructura de :attribute.',
            'integer' => 'El campo :attribute debe ser un número entero.',
            'regex' => 'El campo :attribute tiene un formato inválido.',
            'boolean' => 'Selecciona sí o no en :attribute.',
            'min' => 'El campo :attribute debe ser al menos :min.',
            'max' => 'El campo :attribute supera el límite de :max.',
            'in' => 'Selecciona una opción válida para :attribute.',
            'prohibited' => 'El campo :attribute no se puede modificar desde este formulario.',
            'version.required' => 'Recarga la página y revisa los datos antes de continuar.',
            'version.string' => 'Recarga la página y revisa los datos antes de continuar.',
            'version.regex' => 'Recarga la página y revisa los datos antes de continuar.',
        ];
    }

    public function attributes(): array
    {
        return [
            'buscar' => 'búsqueda', 'estado' => 'estado', 'page' => 'página',
            'experiencia_aplicable' => 'experiencia aplicable', 'justificacion' => 'justificación',
            'version' => 'versión', 'motivo' => 'motivo', 'asignacion_id' => 'asignación',
            'puntuaciones' => 'rúbrica', 'comentarios' => 'comentario general', 'recomendada' => 'recomendación',
            'puntuaciones.tecnico.puntuacion' => 'puntuación de conocimientos técnicos',
            'puntuaciones.tecnico.comentario' => 'comentario de conocimientos técnicos',
            'puntuaciones.blando.puntuacion' => 'puntuación de habilidades blandas',
            'puntuaciones.blando.comentario' => 'comentario de habilidades blandas',
            'puntuaciones.academico.puntuacion' => 'puntuación de requisitos académicos',
            'puntuaciones.academico.comentario' => 'comentario de requisitos académicos',
        ];
    }
}
