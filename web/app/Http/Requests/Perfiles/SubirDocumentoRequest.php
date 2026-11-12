<?php

namespace App\Http\Requests\Perfiles;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

/** D-11: PDF propio de hasta 5 MB, como currículum o evidencia de una habilidad del perfil. */
class SubirDocumentoRequest extends FormRequest
{
    public const MAXIMO_KB = 5120;

    public function authorize(): bool
    {
        return Gate::allows('gestionar-perfil');
    }

    public function rules(): array
    {
        return [
            'tipo' => ['required', 'string', Rule::in(['curriculum', 'evidencia'])],
            'habilidad_id' => ['nullable', 'required_if:tipo,evidencia', 'prohibited_if:tipo,curriculum', 'integer', 'between:-9223372036854775808,9223372036854775807'],
            'archivo' => ['required', 'file', 'mimes:pdf', 'mimetypes:application/pdf', 'max:'.self::MAXIMO_KB],
        ];
    }

    public function messages(): array
    {
        return [
            'archivo.required' => 'Elige un archivo PDF.',
            'archivo.uploaded' => 'No se pudo recibir el archivo. Verifica que sea un PDF de máximo 5 MB.',
            'archivo.file' => 'Elige un archivo PDF.',
            'archivo.mimes' => 'El archivo debe ser un PDF.',
            'archivo.mimetypes' => 'El archivo debe ser un PDF.',
            'archivo.max' => 'El PDF no puede pesar más de 5 MB.',
            'habilidad_id.required_if' => 'Elige la habilidad a la que corresponde la evidencia.',
        ];
    }

    /** Además del tipo declarado, el contenido debe empezar como un PDF real. */
    public function after(): array
    {
        return [function (Validator $validator) {
            $archivo = $this->file('archivo');
            if ($validator->errors()->has('archivo') || ! $archivo || ! $archivo->isValid()) {
                return;
            }
            $inicio = (string) @file_get_contents($archivo->getRealPath(), false, null, 0, 5);
            if ($inicio !== '%PDF-') {
                $validator->errors()->add('archivo', 'El archivo no es un PDF válido.');
            }
        }];
    }
}
