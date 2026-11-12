<?php

namespace App\Services;

use Closure;
use Illuminate\Database\DeadlockException;
use Illuminate\Database\QueryException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

class PublicacionService
{
    public const ESTADOS = [
        'borrador' => 'Borrador', 'en_revision' => 'En revisión', 'en_correccion' => 'En corrección',
        'publicado' => 'Publicado', 'rechazado' => 'Rechazado', 'en_curso' => 'En curso',
        'pausado' => 'Pausado', 'finalizado' => 'Finalizado', 'cancelado' => 'Cancelado',
    ];

    public function empresa(int $actor): object
    {
        return $this->leer('SELECT banco.web_obtener_empresa(?) AS resultado', [$actor]);
    }

    public function editarEmpresa(int $actor, array $datos, string $version): void
    {
        $this->escribir(fn () => DB::selectOne('SELECT banco.web_editar_empresa(?,CAST(? AS jsonb),?)', [
            $actor, $this->json($datos), $version,
        ]), 'No fue posible actualizar la empresa. Revisa sus datos de identificación y contacto.');
    }

    public function listar(int $actor, array $filtros, int $pagina): LengthAwarePaginator
    {
        $porPagina = 20;
        $datos = $this->leer('SELECT banco.web_listar_proyectos(?,?,?,?,?) AS resultado', [
            $actor, $filtros['buscar'] ?? '', $filtros['estado'] ?? '', $porPagina, ($pagina - 1) * $porPagina,
        ]);

        return new LengthAwarePaginator(
            $datos->datos, (int) $datos->total, $porPagina, $pagina,
            ['path' => request()->url(), 'query' => request()->query()],
        );
    }

    public function obtener(int $actor, int $proyecto): object
    {
        $datos = $this->leer('SELECT banco.web_obtener_proyecto(?,?) AS resultado', [$actor, $proyecto]);
        $datos->proyecto->empresa = $datos->empresa;
        $datos->proyecto->habilidades = $datos->habilidades;
        $datos->proyecto->revisiones = $datos->revisiones;

        return $datos->proyecto;
    }

    public function habilidades(int $actor): array
    {
        return $this->leer('SELECT banco.web_catalogo_habilidades(?) AS resultado', [$actor]);
    }

    public function crear(int $actor, array $datos): int
    {
        return (int) $this->escribir(fn () => DB::selectOne(
            'SELECT banco.web_crear_proyecto(?,CAST(? AS jsonb)) AS resultado',
            [$actor, $this->json($datos)],
        )->resultado, 'No fue posible guardar el borrador. Revisa sus datos y las habilidades seleccionadas.');
    }

    public function editar(int $actor, int $proyecto, array $datos, string $version): void
    {
        $this->escribir(fn () => DB::selectOne('SELECT banco.web_editar_proyecto(?,?,CAST(? AS jsonb),?)', [
            $actor, $proyecto, $this->json($datos), $version,
        ]), 'Solo puedes editar un borrador o proyecto devuelto para corrección. Revisa los datos y las habilidades seleccionadas.');
    }

    public function enviar(int $actor, int $proyecto, string $version): int
    {
        $actual = $this->obtener($actor, $proyecto);
        if (! hash_equals($actual->version, $version)) {
            throw ValidationException::withMessages(['operacion' => $this->mensajeConflicto()]);
        }

        // La validación de campos ofrece mensajes útiles; el gateway vuelve a
        // validar estado, contenido y versión bajo bloqueo antes de confirmar.
        Validator::make((array) $actual, [
            'titulo' => ['required', 'string'], 'descripcion' => ['required', 'string'],
            'problematica' => ['required', 'string'], 'objetivos' => ['required', 'string'],
            'justificacion' => ['required', 'string'], 'alcance' => ['required', 'string'],
            'cupo_maximo_alumnos' => ['required', 'integer', 'min:1'],
        ], [
            'required' => 'Completa el campo :attribute antes de enviar el proyecto.',
            'string' => 'Revisa el contenido del campo :attribute.',
            'integer' => 'El cupo máximo de alumnos debe ser un número entero.',
            'min' => 'El cupo máximo de alumnos debe ser positivo.',
        ], [
            'titulo' => 'título', 'descripcion' => 'descripción', 'problematica' => 'problemática',
            'objetivos' => 'objetivos', 'justificacion' => 'justificación', 'alcance' => 'alcance',
            'cupo_maximo_alumnos' => 'cupo máximo de alumnos',
        ])->validate();

        return (int) $this->escribir(fn () => DB::selectOne(
            'SELECT banco.web_enviar_proyecto(?,?,?) AS resultado', [$actor, $proyecto, $version],
        )->resultado, 'El proyecto no puede enviarse desde su estado actual. Completa los seis campos obligatorios y el cupo de alumnos.');
    }

    public function resolver(int $actor, int $proyecto, array $datos): int
    {
        return (int) $this->escribir(fn () => DB::selectOne(
            'SELECT banco.web_resolver_publicacion(?,?,?,?,?,?,?) AS resultado',
            [$actor, $proyecto, (int) $datos['revision_id'], $datos['resultado'], $datos['motivo'],
                isset($datos['cupo_validado']) ? (int) $datos['cupo_validado'] : null, $datos['version']],
        )->resultado, 'Revisa la revisión pendiente, el motivo y el cupo. Para publicar, confirma el mismo cupo que propuso la empresa; devuelve el proyecto si necesita cambios.');
    }

    public function puedeEditar(object $proyecto): bool
    {
        return in_array($proyecto->estado, ['borrador', 'en_correccion'], true)
            && $proyecto->revision_publicada_id === null;
    }

    public function revisionActual(object $proyecto): ?object
    {
        return $proyecto->revisiones[0] ?? null;
    }

    public function puedeResolver(object $proyecto): bool
    {
        return $proyecto->estado === 'en_revision'
            && $this->revisionActual($proyecto)?->estado_revision === 'en_revision';
    }

    private function json(array $datos): string
    {
        return json_encode($datos, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
    }

    private function leer(string $sql, array $parametros): object|array
    {
        try {
            $resultado = DB::selectOne($sql, $parametros)?->resultado;
            abort_if($resultado === null, 404);

            return json_decode($resultado, false, 512, JSON_THROW_ON_ERROR);
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? (string) $error->getCode();
            abort_if($estado === '23503', 404);
            abort_if(in_array($estado, ['23514', '42501'], true), 403);
            Log::error('No fue posible consultar la publicación de proyectos.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
    }

    private function mensajeConflicto(): string
    {
        return 'Los datos cambiaron mientras trabajabas. Recarga la página y revísalos antes de intentar otra vez.';
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
                    '40001', '40P01' => $this->mensajeConflicto(),
                    '23505' => 'La operación ya fue registrada o contiene una habilidad repetida. Recarga y revisa los datos.',
                    '23514', '55000', '22023', '22003', '22007', '22008', '22P02' => $rechazo,
                    default => 'No fue posible completar la operación. Intenta de nuevo más tarde.',
                };
                if (! in_array($estado, ['23505', '40001', '40P01', '23514', '55000', '22023', '22003', '22007', '22008', '22P02'], true)) {
                    Log::error('No se completó la operación de publicación.', ['sqlstate' => $estado]);
                }
                throw ValidationException::withMessages(['operacion' => $mensaje]);
            }
        }

        throw ValidationException::withMessages(['operacion' => 'Intenta de nuevo más tarde.']);
    }
}
