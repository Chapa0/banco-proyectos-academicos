<?php

namespace App\Services;

use Illuminate\Database\QueryException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class CatalogoService
{
    public function listar(int $actor, array $filtros, int $pagina): LengthAwarePaginator
    {
        $porPagina = 20;
        $datos = $this->leer('SELECT banco.web_catalogo_proyectos(?,?,?,?,?,?,?,?) AS resultado', [
            $actor, $filtros['buscar'] ?? '',
            isset($filtros['empresa_id']) ? (int) $filtros['empresa_id'] : null,
            $filtros['modalidad'] ?? '',
            isset($filtros['habilidad_id']) ? (int) $filtros['habilidad_id'] : null,
            $filtros['tipo_habilidad'] ?? '', $porPagina, ($pagina - 1) * $porPagina,
        ]);

        return new LengthAwarePaginator(
            $datos->datos, (int) $datos->total, $porPagina, $pagina,
            ['path' => request()->url(), 'query' => request()->query()],
        );
    }

    public function obtener(int $actor, int $proyecto): object
    {
        $datos = $this->leer('SELECT banco.web_obtener_proyecto_catalogo(?,?) AS resultado', [$actor, $proyecto]);
        $datos->proyecto->empresa = $datos->empresa;
        $datos->proyecto->habilidades = $datos->habilidades;
        $datos->proyecto->disponibilidad = $datos->disponibilidad;

        return $datos->proyecto;
    }

    public function opciones(int $actor): object
    {
        return $this->leer('SELECT banco.web_filtros_catalogo(?) AS resultado', [$actor]);
    }

    private function leer(string $sql, array $parametros): object
    {
        try {
            $resultado = DB::selectOne($sql, $parametros)?->resultado;
            abort_if($resultado === null, 404);
            $datos = json_decode($resultado, false, 512, JSON_THROW_ON_ERROR);
            abort_unless(is_object($datos), 404);

            return $datos;
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? (string) $error->getCode();
            abort_if($estado === '23503', 404);
            abort_if(in_array($estado, ['23514', '42501'], true), 403);
            Log::error('No fue posible consultar el catálogo de proyectos.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
    }
}
