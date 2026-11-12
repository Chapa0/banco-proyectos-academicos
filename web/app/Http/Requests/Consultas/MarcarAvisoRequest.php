<?php

namespace App\Http\Requests\Consultas;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Validator;

class MarcarAvisoRequest extends FormRequest
{
    public function authorize(): bool
    {
        return Gate::allows('consultar-avisos');
    }

    public function rules(): array
    {
        return array_fill_keys([
            'actor', 'actor_usuario_id', 'usuario_id', 'destinatario_usuario_id',
            'id', 'aviso_id', 'notificacion_id', 'evento_id', 'fecha', 'fecha_lectura',
            'mensaje', 'leido', 'estado', 'rol', 'rol_principal', 'recurso', 'enlace',
        ], ['prohibited']);
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            if ($this->allFiles() !== []) {
                $validator->errors()->add('archivos', 'La lectura de un aviso no admite cargar archivos.');
            }
        });
    }

    public function messages(): array
    {
        return ['prohibited' => 'El campo :attribute no se puede modificar desde este aviso.'];
    }
}
