<?php

namespace App\Http\Requests\Perfiles;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Validator;

class GuardarPerfilRequest extends FormRequest
{
    private const CAMPOS_ALUMNO = ['matricula', 'carrera', 'semestre', 'datos_academicos'];

    private const CAMPOS_PROFESOR = ['numero_empleado', 'especialidad', 'experiencia'];

    private const CAMPOS_CONTACTO = ['contacto_correo', 'contacto_telefono'];

    public function authorize(): bool
    {
        return Gate::allows('gestionar-perfil');
    }

    protected function prepareForValidation(): void
    {
        $textos = [];
        foreach (array_merge(self::CAMPOS_ALUMNO, self::CAMPOS_PROFESOR, self::CAMPOS_CONTACTO) as $campo) {
            $valor = $this->input($campo);
            if (is_string($valor)) {
                $textos[$campo] = trim($valor);
            }
        }
        if (isset($textos['contacto_correo'])) {
            $textos['contacto_correo'] = mb_strtolower($textos['contacto_correo']);
        }
        $this->merge($textos);
    }

    public function rules(): array
    {
        $reglas = [
            'version' => ['required', 'string', 'regex:/\A[a-f0-9]{64}\z/'],
            'contacto_correo' => ['nullable', 'string', 'email:rfc', 'max:254'],
            'contacto_telefono' => ['nullable', 'string', 'max:50'],
        ];
        if ($this->user()?->rol_principal === 'alumno') {
            $reglas = array_merge($reglas, [
                'matricula' => ['required', 'string', 'max:100'],
                'carrera' => ['nullable', 'string', 'max:250'],
                'semestre' => ['nullable', 'integer', 'min:1', 'max:32767'],
                'datos_academicos' => ['nullable', 'string', 'max:10000'],
                'habilidades_seleccionadas' => ['nullable', 'array', 'max:200'],
                'habilidades_seleccionadas.*' => ['required', 'integer', 'not_in:0', 'distinct'],
                'niveles' => ['nullable', 'array', 'max:200'],
                'niveles.*' => ['nullable', 'string', 'max:250'],
                'descripciones' => ['nullable', 'array', 'max:200'],
                'descripciones.*' => ['nullable', 'string', 'max:10000'],
                'evidencias' => ['nullable', 'array', 'max:200'],
                'evidencias.*' => ['nullable', 'string', 'max:10000'],
            ], array_fill_keys(self::CAMPOS_PROFESOR, ['prohibited']));
        } else {
            $reglas = array_merge($reglas, [
                'numero_empleado' => ['required', 'string', 'max:100'],
                'especialidad' => ['nullable', 'string', 'max:1000'],
                'experiencia' => ['nullable', 'string', 'max:10000'],
            ], array_fill_keys(array_merge(self::CAMPOS_ALUMNO, [
                'habilidades_seleccionadas', 'niveles', 'descripciones', 'evidencias',
            ]), ['prohibited']));
        }

        return array_merge($reglas, array_fill_keys([
            'actor', 'actor_usuario_id', 'id', 'usuario_id', 'alumno_id', 'profesor_id', 'titular_id',
            'empresa_id', 'rol', 'rol_principal', 'estado_cuenta', 'nombre', 'correo',
            'hash_contrasena', 'password', 'habilidades',
        ], ['prohibited']));
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            if ($this->allFiles() !== []) {
                $validator->errors()->add('archivos', 'Las evidencias son texto o enlaces escritos; no se admite cargar archivos.');
            }
        });
    }

    public function datos(): array
    {
        $validados = $this->validated();
        $campos = $this->user()->rol_principal === 'alumno' ? self::CAMPOS_ALUMNO : self::CAMPOS_PROFESOR;
        $datos = [];
        foreach (array_merge($campos, self::CAMPOS_CONTACTO) as $campo) {
            $datos[$campo] = $validados[$campo] ?? null;
        }
        if ($this->user()->rol_principal === 'alumno') {
            $datos['semestre'] = isset($datos['semestre']) ? (int) $datos['semestre'] : null;
            $datos['habilidades'] = [];
            foreach ($validados['habilidades_seleccionadas'] ?? [] as $id) {
                $datos['habilidades'][] = [
                    'habilidad_id' => (int) $id,
                    'nivel_dominio' => $this->textoOpcional($validados['niveles'][$id] ?? null),
                    'descripcion' => $this->textoOpcional($validados['descripciones'][$id] ?? null),
                    'evidencia' => $this->textoOpcional($validados['evidencias'][$id] ?? null),
                ];
            }
        }

        return $datos;
    }

    private function textoOpcional(mixed $valor): ?string
    {
        return is_string($valor) && trim($valor) !== '' ? trim($valor) : null;
    }

    public function messages(): array
    {
        return [
            'required' => 'El campo :attribute es obligatorio.',
            'string' => 'El campo :attribute debe ser texto.',
            'array' => 'Revisa la selección de :attribute.',
            'integer' => 'El campo :attribute debe ser un número entero.',
            'min' => 'El campo :attribute debe ser al menos :min.',
            'max' => 'El campo :attribute supera el límite de :max.',
            'distinct' => 'No repitas una habilidad en la selección.',
            'prohibited' => 'El campo :attribute no se puede modificar desde este perfil.',
            'contacto_correo.email' => 'Indica un correo de contacto válido.',
            'version.required' => 'Recarga la página y revisa tu perfil antes de continuar.',
            'version.string' => 'Recarga la página y revisa tu perfil antes de continuar.',
            'version.regex' => 'Recarga la página y revisa tu perfil antes de continuar.',
        ];
    }

    public function attributes(): array
    {
        return [
            'matricula' => 'matrícula', 'carrera' => 'carrera', 'semestre' => 'semestre',
            'datos_academicos' => 'datos académicos', 'numero_empleado' => 'número de empleado',
            'especialidad' => 'especialidad', 'experiencia' => 'experiencia',
            'contacto_correo' => 'correo de contacto', 'contacto_telefono' => 'teléfono de contacto',
            'habilidades_seleccionadas' => 'habilidades', 'habilidades_seleccionadas.*' => 'habilidad',
            'niveles' => 'niveles', 'niveles.*' => 'nivel de dominio',
            'descripciones' => 'descripciones', 'descripciones.*' => 'descripción de habilidad',
            'evidencias' => 'evidencias', 'evidencias.*' => 'evidencia', 'version' => 'versión',
        ];
    }
}
