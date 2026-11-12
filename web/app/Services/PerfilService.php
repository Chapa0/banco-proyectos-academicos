<?php

namespace App\Services;

use Closure;
use Illuminate\Database\DeadlockException;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

class PerfilService
{
    public function obtener(int $actor): object
    {
        return $this->leer('SELECT banco.web_obtener_perfil_propio(?) AS resultado', [$actor]);
    }

    public function habilidades(int $actor): array
    {
        return $this->leer('SELECT banco.web_listar_habilidades_perfil(?) AS resultado', [$actor]);
    }

    /**
     * Avance del perfil propio (UX-02): datos recomendados para que empresas y administración evalúen
     * mejor. Solo orienta; los obligatorios siguen validándose al guardar y al participar.
     *
     * @param  object  $actual  resultado de obtener()
     */
    public function completitud(object $actual): object
    {
        $perfil = $actual->perfil ?? null;
        $lleno = fn (string $campo) => isset($perfil->{$campo}) && trim((string) $perfil->{$campo}) !== '';
        $campos = $actual->rol === 'alumno'
            ? ['matricula' => 'tu matrícula', 'carrera' => 'tu carrera', 'semestre' => 'tu semestre',
                'datos_academicos' => 'tu formación', 'contacto_correo' => 'un correo de contacto', 'contacto_telefono' => 'un teléfono de contacto']
            : ['numero_empleado' => 'tu número de empleado', 'especialidad' => 'tus áreas de especialidad',
                'experiencia' => 'tu experiencia', 'contacto_correo' => 'un correo de contacto', 'contacto_telefono' => 'un teléfono de contacto'];
        $faltantes = [];
        foreach ($campos as $campo => $texto) {
            if (! $lleno($campo)) {
                $faltantes[] = (object) ['campo' => 'campo-'.$campo, 'texto' => $texto];
            }
        }
        $total = count($campos);
        if ($actual->rol === 'alumno') {
            $total++;
            if (count($actual->habilidades ?? []) === 0) {
                $faltantes[] = (object) ['campo' => 'habilidades-ayuda', 'texto' => 'al menos una habilidad'];
            }
        }

        return (object) [
            'porcentaje' => (int) round(($total - count($faltantes)) * 100 / $total),
            'faltantes' => $faltantes,
        ];
    }

    public function guardar(int $actor, array $datos, string $version): void
    {
        $identificador = array_key_exists('matricula', $datos) ? 'matricula' : 'numero_empleado';
        $this->escribir(fn () => DB::selectOne('SELECT banco.web_guardar_perfil_propio(?,CAST(? AS jsonb),?)', [
            $actor, json_encode($datos, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE), $version,
        ]), $identificador);
    }

    private function leer(string $sql, array $parametros): object|array
    {
        try {
            $resultado = DB::selectOne($sql, $parametros)?->resultado;
            abort_if($resultado === null, 404);
            $datos = json_decode($resultado, false, 512, JSON_THROW_ON_ERROR);
            abort_unless(is_object($datos) || is_array($datos), 404);

            return $datos;
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? (string) $error->getCode();
            abort_if($estado === '23503', 404);
            abort_if(in_array($estado, ['23514', '42501'], true), 403);
            Log::error('No fue posible consultar el perfil académico.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
    }

    private function escribir(Closure $operacion, string $identificador): void
    {
        $transaccionExterna = DB::transactionLevel() > 0;
        for ($intento = 1; $intento <= 3; $intento++) {
            try {
                DB::transaction($operacion, 1);

                return;
            } catch (QueryException|DeadlockException $error) {
                $origen = $error instanceof DeadlockException ? $error->getPrevious() : $error;
                $estado = $origen instanceof QueryException ? ($origen->errorInfo[0] ?? (string) $origen->getCode()) : '40P01';
                if ($estado === '40P01' && $intento < 3 && ! $transaccionExterna) {
                    continue;
                }
                abort_if($estado === '42501', 403);
                $mensaje = match ($estado) {
                    '40001', '40P01' => 'Tu perfil cambió mientras trabajabas. Recarga la página y revísalo antes de intentar otra vez.',
                    '23505' => $identificador === 'matricula'
                        ? 'La matrícula ya está asociada a otro alumno.'
                        : 'El número de empleado ya está asociado a otro profesor.',
                    '23503' => 'Alguna habilidad ya no está disponible. Recarga la página y revisa tu selección.',
                    '23514', '55000', '22023', '22003', '22P02' => 'No fue posible guardar el perfil. Revisa los datos académicos y las habilidades seleccionadas.',
                    default => 'No fue posible completar la operación. Intenta de nuevo más tarde.',
                };
                if (! in_array($estado, ['40001', '40P01', '23505', '23503', '23514', '55000', '22023', '22003', '22P02'], true)) {
                    Log::error('No se completó la edición del perfil académico.', ['sqlstate' => $estado]);
                }
                $campo = match ($estado) {
                    '23505' => $identificador,
                    '23503' => 'habilidades_seleccionadas',
                    default => 'operacion',
                };
                throw ValidationException::withMessages([$campo => $mensaje]);
            }
        }
    }
}
