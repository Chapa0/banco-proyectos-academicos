<?php

namespace App\Services;

use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Coincidencia entre habilidades requeridas por un proyecto y las registradas por un alumno (UX-02).
 * Regla: una habilidad requerida se cumple si el alumno la tiene en su perfil; el nivel es texto libre
 * y no se compara. Solo orienta: no bloquea candidaturas ni sustituye la evaluación de la empresa.
 */
class CoincidenciaService
{
    /**
     * Coincidencia del alumno actor con proyectos publicados, calculada en PostgreSQL (025).
     * Devuelve [id_proyecto => objeto]; los proyectos sin habilidades requeridas no aparecen.
     *
     * @param  array<int>  $proyectos
     * @return array<int, object>
     */
    public function catalogo(int $actor, array $proyectos): array
    {
        if ($proyectos === []) {
            return [];
        }
        try {
            $resultado = DB::selectOne('SELECT banco.web_coincidencia_catalogo(?,CAST(? AS bigint[])) AS resultado', [
                $actor, '{'.implode(',', array_map('intval', $proyectos)).'}',
            ])?->resultado;
            $datos = json_decode($resultado ?? '{}', true, 512, JSON_THROW_ON_ERROR);
        } catch (QueryException $error) {
            // Es una ayuda: si falla, el catálogo se muestra igual, sin la coincidencia.
            Log::warning('No fue posible calcular la coincidencia de habilidades.', ['sqlstate' => $error->errorInfo[0] ?? null]);

            return [];
        }
        $salida = [];
        foreach (is_array($datos) ? $datos : [] as $id => $item) {
            $salida[(int) $id] = $this->resumen((int) $item['requeridas'], (int) $item['cumplidas'], $item['faltantes'] ?? []);
        }

        return $salida;
    }

    /**
     * «Recomendados para ti» (UX-06, 027): proyectos con plazas donde el alumno aún no participa,
     * ordenados por obligatorias cumplidas y proporción de coincidencia. Profesor: lista vacía.
     *
     * @return list<object> cada uno con id, titulo, razon_social, descripcion, modalidad, plazas y coincidencia
     */
    public function recomendaciones(int $actor, int $limite = 3): array
    {
        try {
            $resultado = DB::selectOne('SELECT banco.web_recomendaciones(?,?) AS resultado', [$actor, $limite])?->resultado;
            $datos = json_decode($resultado ?? '[]', true, 512, JSON_THROW_ON_ERROR);
        } catch (QueryException $error) {
            // Es una ayuda: si falla, la página se muestra sin recomendaciones.
            Log::warning('No fue posible calcular las recomendaciones.', ['sqlstate' => $error->errorInfo[0] ?? null]);

            return [];
        }

        return array_map(function (array $item) {
            $c = $item['coincidencia'];
            unset($item['coincidencia']);
            $proyecto = (object) $item;
            $proyecto->coincidencia = $this->resumen((int) $c['requeridas'], (int) $c['cumplidas'], $c['faltantes'] ?? []);

            return $proyecto;
        }, is_array($datos) ? array_values($datos) : []);
    }

    /**
     * Misma regla, en PHP, para quien ya obtuvo ambos conjuntos con permiso (empresa o administrador
     * al revisar una candidatura de su ámbito).
     *
     * @param  array<object>  $requeridas  elementos con habilidad_id, nombre y obligatoria
     * @param  array<object>  $propias  elementos con habilidad_id
     */
    public function calcular(array $requeridas, array $propias): ?object
    {
        if ($requeridas === []) {
            return null;
        }
        $ids = array_map(fn ($h) => (int) $h->habilidad_id, $propias);
        $faltantes = [];
        foreach ($requeridas as $habilidad) {
            if (! in_array((int) $habilidad->habilidad_id, $ids, true)) {
                $faltantes[] = ['nombre' => (string) $habilidad->nombre, 'obligatoria' => (bool) ($habilidad->obligatoria ?? false)];
            }
        }
        usort($faltantes, fn ($a, $b) => [! $a['obligatoria'], $a['nombre']] <=> [! $b['obligatoria'], $b['nombre']]);

        return $this->resumen(count($requeridas), count($requeridas) - count($faltantes), $faltantes);
    }

    private function resumen(int $requeridas, int $cumplidas, array $faltantes): object
    {
        $faltantes = array_map(fn ($f) => (object) ['nombre' => (string) $f['nombre'], 'obligatoria' => (bool) $f['obligatoria']], $faltantes);

        return (object) [
            'requeridas' => $requeridas,
            'cumplidas' => $cumplidas,
            'faltantes' => $faltantes,
            'faltan_obligatorias' => count(array_filter($faltantes, fn ($f) => $f->obligatoria)),
            'nivel' => $cumplidas === $requeridas ? 'completa' : ($cumplidas * 2 >= $requeridas ? 'parcial' : 'baja'),
        ];
    }
}
