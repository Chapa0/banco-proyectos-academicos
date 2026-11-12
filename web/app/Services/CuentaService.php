<?php

namespace App\Services;

use Closure;
use Illuminate\Database\DeadlockException;
use Illuminate\Database\QueryException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

class CuentaService
{
    public function listar(int $admin, array $filtros, int $pagina): LengthAwarePaginator
    {
        $porPagina = 20;
        $datos = $this->leer('SELECT banco.web_listar_cuentas(?,?,?,?,?,?) AS resultado', [
            $admin, $filtros['buscar'] ?? '', $filtros['rol'] ?? '', $filtros['estado'] ?? '',
            $porPagina, ($pagina - 1) * $porPagina,
        ]);

        return new LengthAwarePaginator(
            array_map(fn (array $cuenta): object => (object) $cuenta, $datos['datos']),
            (int) $datos['total'], $porPagina, $pagina,
            ['path' => request()->url(), 'query' => request()->query()],
        );
    }

    public function obtener(int $admin, int $cuenta): object
    {
        return (object) $this->leer('SELECT banco.web_obtener_cuenta(?,?) AS resultado', [$admin, $cuenta]);
    }

    public function crear(int $admin, array $datos): int
    {
        $hash = Hash::make($datos['password']);

        return (int) $this->escribir(fn () => DB::selectOne(
            'SELECT banco.web_crear_cuenta(?,?,?,?,?,?) AS resultado',
            [$admin, $datos['nombre'], $datos['correo'], $hash, $datos['rol'], $datos['razon_social'] ?? null],
        )->resultado, 'Revisa los datos de la cuenta y el rol seleccionado.');
    }

    public function editar(int $admin, int $cuenta, array $datos): void
    {
        $this->escribir(fn () => DB::selectOne('SELECT banco.web_editar_cuenta(?,?,?,?,?,?)', [
            $admin, $cuenta, $datos['nombre'], $datos['correo'], $datos['motivo'], (int) $datos['version_acceso'],
        ]), 'No fue posible editar la cuenta con los datos indicados.');
    }

    public function cambiarEstado(int $admin, int $cuenta, array $datos): void
    {
        $this->escribir(fn () => DB::selectOne('SELECT banco.web_estado_cuenta(?,?,?,?,?)', [
            $admin, $cuenta, $datos['estado'], $datos['motivo'], (int) $datos['version_acceso'],
        ]), 'No se pudo cambiar el estado. Conserva un administrador activo y usa el relevo para sustituir al representante vigente.');
    }

    public function restablecerClave(int $admin, int $cuenta, array $datos): void
    {
        $hash = Hash::make($datos['password']);
        $this->escribir(fn () => DB::selectOne('SELECT banco.web_restablecer_clave(?,?,?,?,?)', [
            $admin, $cuenta, $hash, $datos['motivo'], (int) $datos['version_acceso'],
        ]), 'No fue posible restablecer la contraseña de esta cuenta.');
    }

    public function relevar(int $admin, object $cuenta, array $datos): int
    {
        $hash = Hash::make($datos['password']);

        return (int) $this->escribir(fn () => DB::selectOne(
            'SELECT banco.web_relevar_representante(?,?,?,?,?,?,?) AS resultado',
            [$admin, $cuenta->empresa_id, $datos['nombre'], $datos['correo'], $hash, $datos['motivo'], $cuenta->id],
        )->resultado, 'El relevo requiere una empresa con un representante vigente y un administrador activo.');
    }

    private function leer(string $sql, array $parametros): array
    {
        try {
            $resultado = DB::selectOne($sql, $parametros)?->resultado;
            abort_if($resultado === null, 404);

            return json_decode($resultado, true, 512, JSON_THROW_ON_ERROR);
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? (string) $error->getCode();
            abort_if($estado === '23503', 404);
            abort_if(in_array($estado, ['23514', '42501'], true), 403);
            Log::error('No fue posible consultar las cuentas.', ['sqlstate' => $estado]);
            abort(503, 'No fue posible consultar las cuentas. Intenta de nuevo más tarde.');
        }
    }

    private function escribir(Closure $operacion, string $rechazo): mixed
    {
        $transaccionExterna = DB::transactionLevel() > 0;
        for ($intento = 1; $intento <= 3; $intento++) {
            try {
                // Un conflicto de versión requiere datos nuevos del formulario;
                // solo se reintenta un interbloqueo, nunca ese 40001 obsoleto.
                return DB::transaction($operacion, 1);
            } catch (QueryException|DeadlockException $error) {
                $origen = $error instanceof DeadlockException ? $error->getPrevious() : $error;
                $estado = $origen instanceof QueryException ? ($origen->errorInfo[0] ?? (string) $origen->getCode()) : '40P01';
                if ($estado === '40P01' && $intento < 3 && ! $transaccionExterna) {
                    continue;
                }
                $mensaje = match ($estado) {
                    '23505' => 'El correo ya está asociado a una cuenta.',
                    '40001', '40P01' => 'La cuenta cambió mientras la editabas. Recarga la página y revisa los datos antes de intentar otra vez.',
                    '23503' => 'La cuenta o empresa ya no está disponible. Recarga la página.',
                    '23514', '42501', '55000', '22023' => $rechazo,
                    default => 'No fue posible completar la operación. Intenta de nuevo más tarde.',
                };
                if (! in_array($estado, ['23505', '40001', '40P01', '23503', '23514', '42501', '55000', '22023'], true)) {
                    Log::error('No se completó la operación de cuentas.', ['sqlstate' => $estado]);
                }
                throw ValidationException::withMessages([
                    $estado === '23505' ? 'correo' : 'operacion' => $mensaje,
                ]);
            }
        }

        throw ValidationException::withMessages(['operacion' => 'Intenta de nuevo más tarde.']);
    }
}
