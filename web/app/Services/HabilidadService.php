<?php

namespace App\Services;

use Illuminate\Database\QueryException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

/** UX-10: catálogo de habilidades mantenido por la administración (031). */
class HabilidadService
{
    public const TIPOS = ['dura' => 'Dura', 'blanda' => 'Blanda'];

    /** @return array{0: LengthAwarePaginator, 1: object} página y resumen del catálogo */
    public function listar(int $admin, array $filtros): array
    {
        $pagina = (int) ($filtros['page'] ?? 1);
        try {
            $datos = json_decode((string) DB::selectOne('SELECT banco.web_habilidades_admin(?,?,?,?,?) AS resultado', [
                $admin, $filtros['buscar'] ?? '', $filtros['tipo'] ?? '', 25, ($pagina - 1) * 25,
            ])->resultado, false, 512, JSON_THROW_ON_ERROR);
        } catch (QueryException $error) {
            $this->abortar($error, 'No fue posible consultar el catálogo de habilidades.');
        }

        return [new LengthAwarePaginator($datos->datos, (int) $datos->total, 25, $pagina, [
            'path' => request()->url(), 'query' => request()->query(),
        ]), $datos->resumen];
    }

    public function guardar(int $admin, ?int $id, array $datos): int
    {
        try {
            return (int) DB::transaction(fn () => DB::selectOne('SELECT banco.web_guardar_habilidad(?,?,?,?,?) AS id', [
                $admin, $id, $datos['nombre'], $datos['tipo'], $datos['descripcion'] ?? null,
            ])->id, 1);
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? null;
            if ($estado === '23505') {
                throw ValidationException::withMessages(['nombre' => 'Ya existe una habilidad con ese nombre (sin contar mayúsculas, acentos ni espacios). Usa la existente o elige otro nombre.']);
            }
            if ($estado === '23514') {
                throw ValidationException::withMessages(['nombre' => 'Revisa el nombre, el tipo y la descripción.']);
            }
            $this->abortar($error, 'No se guardó una habilidad del catálogo.');
        }
    }

    public function eliminar(int $admin, int $id): void
    {
        try {
            DB::transaction(fn () => DB::select('SELECT banco.web_eliminar_habilidad(?,?)', [$admin, $id]), 1);
        } catch (QueryException $error) {
            if (($error->errorInfo[0] ?? null) === '55000') {
                throw ValidationException::withMessages(['habilidad' => 'Esa habilidad ya se usa en perfiles, proyectos o evidencias, así que se conserva. Puedes cambiarle el nombre o la descripción.']);
            }
            $this->abortar($error, 'No se eliminó una habilidad del catálogo.');
        }
    }

    private function abortar(QueryException $error, string $mensaje): never
    {
        $estado = $error->errorInfo[0] ?? null;
        abort_if($estado === '23503', 404);
        abort_if($estado === '42501', 403);
        Log::error($mensaje, ['sqlstate' => $estado]);
        abort(503, 'El servicio no está disponible en este momento.');
    }
}
