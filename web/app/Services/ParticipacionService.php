<?php

namespace App\Services;

use Closure;
use Illuminate\Database\DeadlockException;
use Illuminate\Database\QueryException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

class ParticipacionService
{
    public const TIPOS = ['candidatura' => 'Candidaturas', 'direccion' => 'Solicitudes de dirección'];

    public const ESTADOS_CANDIDATURA = [
        'pendiente_evaluacion' => 'Pendiente de evaluación', 'evaluada' => 'Evaluada',
        'preseleccionada' => 'Preseleccionada', 'aprobada' => 'Aprobada',
        'rechazada' => 'Rechazada', 'cancelada' => 'Cancelada',
    ];

    public const ESTADOS_DIRECCION = [
        'pendiente' => 'Pendiente', 'aprobada' => 'Aprobada',
        'rechazada' => 'Rechazada', 'cancelada' => 'Cancelada',
    ];

    public function listar(int $actor, string $tipo, array $filtros): LengthAwarePaginator
    {
        $pagina = (int) ($filtros['page'] ?? 1);
        $datos = $this->leer('SELECT banco.web_bandeja_participacion(?,?,?,?,?,?) AS resultado', [
            $actor, $tipo, $filtros['estado'] ?? '', $filtros['buscar'] ?? '', 20, ($pagina - 1) * 20,
        ]);

        return $this->paginar($datos, $pagina);
    }

    public function obtener(int $actor, string $tipo, int $solicitud): object
    {
        return $this->leer('SELECT banco.web_detalle_participacion(?,?,?) AS resultado', [$actor, $tipo, $solicitud]);
    }

    public function contexto(int $actor, int $proyecto): object
    {
        return $this->leer('SELECT banco.web_contexto_postulacion(?,?) AS resultado', [$actor, $proyecto]);
    }

    public function enviar(int $actor, int $proyecto, array $datos, string $version): int
    {
        return (int) $this->escribir(fn () => DB::selectOne(
            'SELECT banco.web_enviar_participacion(?,?,CAST(? AS jsonb),?) AS resultado',
            [$actor, $proyecto, $this->json($datos), $version],
        )->resultado, 'Revisa tu perfil, la disponibilidad del proyecto y tus solicitudes activas antes de enviar.');
    }

    public function operar(int $actor, string $tipo, int $solicitud, string $accion, array $datos, string $version): void
    {
        $this->escribir(fn () => DB::selectOne(
            'SELECT banco.web_operar_participacion(?,?,?,?,CAST(? AS jsonb),?)',
            [$actor, $tipo, $solicitud, $accion, $this->json($datos), $version],
        ), 'La solicitud no admite esta operación. Revisa su estado, evaluación, cupos y carga antes de continuar.');
    }

    public function proyectos(int $actor, array $filtros): LengthAwarePaginator
    {
        $pagina = (int) ($filtros['page'] ?? 1);
        $datos = $this->leer('SELECT banco.web_proyectos_participacion(?,?,?,?,?) AS resultado', [
            $actor, $filtros['estado'] ?? '', $filtros['buscar'] ?? '', 20, ($pagina - 1) * 20,
        ]);

        return $this->paginar($datos, $pagina);
    }

    public function proyecto(int $actor, int $proyecto): object
    {
        return $this->leer('SELECT banco.web_detalle_proyecto_participacion(?,?) AS resultado', [$actor, $proyecto]);
    }

    public function operarProyecto(int $actor, int $proyecto, string $accion, array $datos, string $version): void
    {
        $this->escribir(fn () => DB::selectOne(
            'SELECT banco.web_operar_proyecto_participacion(?,?,?,CAST(? AS jsonb),?)',
            [$actor, $proyecto, $accion, $this->json($datos), $version],
        ), 'El proyecto no admite esta operación. Revisa su estado, participantes autorizados, cupos y carga.');
    }

    public function estados(string $tipo): array
    {
        return $tipo === 'candidatura' ? self::ESTADOS_CANDIDATURA : self::ESTADOS_DIRECCION;
    }

    private function paginar(object $datos, int $pagina): LengthAwarePaginator
    {
        return new LengthAwarePaginator($datos->datos, (int) $datos->total, 20, $pagina, [
            'path' => request()->url(), 'query' => request()->query(),
        ]);
    }

    private function json(array $datos): string
    {
        // Un payload vacío también representa un objeto, no una lista JSON.
        return json_encode((object) $datos, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
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
            Log::error('No fue posible consultar la participación en proyectos.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
    }

    private function escribir(Closure $operacion, string $rechazo): mixed
    {
        $transaccionExterna = DB::transactionLevel() > 0;
        for ($intento = 1; $intento <= 3; $intento++) {
            try {
                return DB::transaction($operacion, 1);
            } catch (QueryException|DeadlockException $error) {
                $origen = $error instanceof DeadlockException ? $error->getPrevious() : $error;
                $estado = $origen instanceof QueryException ? ($origen->errorInfo[0] ?? (string) $origen->getCode()) : '40P01';
                if ($estado === '40P01' && $intento < 3 && ! $transaccionExterna) {
                    continue;
                }
                abort_if($estado === '42501', 403);
                abort_if($estado === '23503', 404);
                $mensaje = match ($estado) {
                    '40001', '40P01' => 'Los datos cambiaron mientras trabajabas. Recarga la página y revísalos antes de intentar otra vez.',
                    '23505' => 'Ya existe una solicitud o asignación vigente para esta participación. Recarga y revisa tus registros.',
                    '23514', '55000', '22023', '22003', '22P02' => $rechazo,
                    default => 'No fue posible completar la operación. Intenta de nuevo más tarde.',
                };
                if (! in_array($estado, ['40001', '40P01', '23505', '23514', '55000', '22023', '22003', '22P02'], true)) {
                    Log::error('No se completó la operación de participación.', ['sqlstate' => $estado]);
                }
                throw ValidationException::withMessages(['operacion' => $mensaje]);
            }
        }

        throw ValidationException::withMessages(['operacion' => 'Intenta de nuevo más tarde.']);
    }
}
