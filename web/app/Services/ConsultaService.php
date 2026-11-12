<?php

namespace App\Services;

use Carbon\CarbonImmutable;
use Illuminate\Database\QueryException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

class ConsultaService
{
    public const ESTADOS_AVISO = ['todos' => 'Todos', 'no_leidos' => 'No leídos', 'leidos' => 'Leídos'];

    public const TIPOS_REPORTE = [
        'proyectos' => 'Proyectos', 'candidaturas' => 'Candidaturas',
        'direcciones' => 'Solicitudes de dirección', 'carga_profesores' => 'Carga de profesores',
        'asignaciones' => 'Participantes asignados',
    ];

    public const FILTROS_REPORTE = [
        'proyectos' => ['empresa_id'], 'candidaturas' => ['empresa_id', 'proyecto_id'],
        'direcciones' => ['empresa_id', 'proyecto_id', 'profesor_id'],
        'carga_profesores' => ['profesor_id'], 'asignaciones' => ['empresa_id', 'proyecto_id'],
    ];

    /** Columnas visibles de cada reporte; la vista y la exportación usan las mismas. */
    public const COLUMNAS_REPORTE = [
        'proyectos' => ['titulo' => 'Proyecto', 'razon_social' => 'Empresa', 'estado' => 'Estado', 'cupo_maximo_alumnos' => 'Cupo de alumnos', 'alumnos_vigentes' => 'Alumnos vigentes', 'directores_vigentes' => 'Directores vigentes'],
        'candidaturas' => ['titulo' => 'Proyecto', 'razon_social' => 'Empresa', 'solicitante_nombre' => 'Alumno', 'estado' => 'Estado', 'fecha_solicitud' => 'Fecha de solicitud'],
        'direcciones' => ['titulo' => 'Proyecto', 'razon_social' => 'Empresa', 'solicitante_nombre' => 'Profesor', 'estado' => 'Estado', 'fecha_solicitud' => 'Fecha de solicitud'],
        'carga_profesores' => ['nombre' => 'Profesor', 'proyectos_vigentes' => 'Proyectos vigentes', 'limite_proyectos' => 'Límite de proyectos'],
        'asignaciones' => ['titulo' => 'Proyecto', 'razon_social' => 'Empresa', 'participante_nombre' => 'Participante', 'tipo' => 'Participación', 'estado' => 'Estado', 'inicio' => 'Desde', 'fin' => 'Hasta'],
    ];

    public const MAXIMO_EXPORTACION = 5000;

    public function avisos(int $actor, array $filtros): object
    {
        $pagina = (int) ($filtros['page'] ?? 1);
        $datos = $this->consultar('SELECT banco.web_bandeja_avisos(?,?,?,?,?) AS resultado', [
            $actor, $filtros['estado'] ?? 'todos', $filtros['buscar'] ?? '', 20, ($pagina - 1) * 20,
        ]);
        $datos->pagina = $this->paginar($datos, $pagina);

        return $datos;
    }

    public function aviso(int $actor, int $aviso): object
    {
        return $this->consultar('SELECT banco.web_detalle_aviso(?,?) AS resultado', [$actor, $aviso]);
    }

    public function leerAviso(int $actor, int $aviso): void
    {
        try {
            DB::transaction(fn () => DB::selectOne('SELECT banco.web_leer_aviso(?,?)', [$actor, $aviso]), 1);
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? (string) $error->getCode();
            abort_if($estado === '23503', 404);
            abort_if(in_array($estado, ['23514', '42501'], true), 403);
            if (in_array($estado, ['40001', '40P01'], true)) {
                throw ValidationException::withMessages(['operacion' => 'No fue posible registrar la lectura. Recarga el aviso e intenta de nuevo.']);
            }
            Log::error('No fue posible registrar la lectura del aviso.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
    }

    public function reporte(int $actor, string $tipo, array $filtros): object
    {
        $pagina = (int) ($filtros['page'] ?? 1);
        $datos = $this->bloqueReporte($actor, $tipo, $filtros, 20, ($pagina - 1) * 20);
        $datos->pagina = $this->paginar($datos, $pagina);

        return $datos;
    }

    /**
     * Filas del reporte completo con los mismos filtros (UX-05), leídas por bloques de 100 con el
     * gateway del reporte. La base exige READ COMMITTED (banco.exigir_aislamiento), así que no hay
     * instantánea única: si el total cambia entre bloques se pide repetir en vez de entregar un archivo mezclado.
     *
     * @return array{columnas: array<string,string>, filas: list<list<string>>}
     */
    public function exportarReporte(int $actor, string $tipo, array $filtros): array
    {
        unset($filtros['page']);
        $columnas = self::COLUMNAS_REPORTE[$tipo];
        $filas = [];
        $desplazamiento = 0;
        $total = null;
        do {
            $bloque = $this->bloqueReporte($actor, $tipo, $filtros, 100, $desplazamiento);
            if ($total === null && (int) $bloque->total > self::MAXIMO_EXPORTACION) {
                throw ValidationException::withMessages(['exportar' => 'El reporte tiene '.$bloque->total.' registros y se pueden exportar hasta '
                    .number_format(self::MAXIMO_EXPORTACION).'. Usa los filtros para reducirlo.']);
            }
            if ($total !== null && $total !== (int) $bloque->total) {
                throw ValidationException::withMessages(['exportar' => 'Los datos cambiaron mientras se preparaba el archivo. Vuelve a exportar el reporte.']);
            }
            $total = (int) $bloque->total;
            array_push($filas, ...$bloque->datos);
            $desplazamiento += 100;
        } while ($desplazamiento < $total && $bloque->datos !== []);
        if (count($filas) !== $total) {
            throw ValidationException::withMessages(['exportar' => 'Los datos cambiaron mientras se preparaba el archivo. Vuelve a exportar el reporte.']);
        }
        $estados = ['vigente' => 'Vigente', 'finalizada' => 'Finalizada', 'revocada' => 'Revocada']
            + PublicacionService::ESTADOS + ParticipacionService::ESTADOS_CANDIDATURA + ParticipacionService::ESTADOS_DIRECCION;

        return ['columnas' => $columnas, 'filas' => array_map(fn (object $fila) => array_map(
            fn (string $campo) => $this->valorExportado($campo, $fila->{$campo} ?? null, $estados), array_keys($columnas),
        ), $filas)];
    }

    private function valorExportado(string $campo, mixed $valor, array $estados): string
    {
        if ($valor === null || $valor === '') {
            return $campo === 'fin' ? 'Sin fecha final' : '';
        }

        return match (true) {
            $campo === 'estado' => $estados[$valor] ?? (string) $valor,
            $campo === 'tipo' => $valor === 'alumno' ? 'Alumno' : 'Dirección',
            in_array($campo, ['fecha_solicitud', 'inicio', 'fin'], true) => CarbonImmutable::parse($valor)->setTimezone('America/Mexico_City')->format('Y-m-d H:i'),
            default => (string) $valor,
        };
    }

    private function bloqueReporte(int $actor, string $tipo, array $filtros, int $limite, int $desplazamiento): object
    {
        unset($filtros['page']);
        foreach (self::FILTROS_REPORTE[$tipo] as $campo) {
            if (isset($filtros[$campo])) {
                $filtros[$campo] = (int) $filtros[$campo];
            }
        }

        return $this->consultar('SELECT banco.web_reporte(?,?,CAST(? AS jsonb),?,?) AS resultado', [
            $actor, $tipo, json_encode((object) $filtros, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE), $limite, $desplazamiento,
        ]);
    }

    public function estadosReporte(string $tipo): array
    {
        return match ($tipo) {
            'proyectos' => PublicacionService::ESTADOS,
            'candidaturas' => ParticipacionService::ESTADOS_CANDIDATURA,
            'direcciones' => ParticipacionService::ESTADOS_DIRECCION,
            'asignaciones' => ['vigente' => 'Vigente', 'finalizada' => 'Finalizada', 'revocada' => 'Revocada'],
            default => [],
        };
    }

    private function paginar(object $datos, int $pagina): LengthAwarePaginator
    {
        return new LengthAwarePaginator($datos->datos, (int) $datos->total, 20, $pagina, [
            'path' => request()->url(), 'query' => request()->query(),
        ]);
    }

    private function consultar(string $sql, array $parametros): object
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
            Log::error('No fue posible consultar los avisos o reportes.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
    }
}
