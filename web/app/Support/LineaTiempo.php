<?php

namespace App\Support;

/**
 * Pasos de la línea de tiempo del estado (UX-06). Solo presenta datos ya autorizados por los gateways
 * de detalle: no consulta la base ni decide transiciones. Cada paso es
 * ['etiqueta' => string, 'estado' => hecho|actual|pendiente|detenido, 'fecha' => ?string].
 */
class LineaTiempo
{
    /** @return list<array{etiqueta:string,estado:string,fecha:?string}> */
    public static function participacion(string $tipo, object $detalle): array
    {
        $solicitud = $detalle->solicitud;
        $estado = $solicitud->estado;
        $historial = self::porOperacion($detalle->historial ?? []);
        $decision = collect($detalle->decisiones ?? [])->sortBy('fecha')->last();
        $asignacion = $detalle->asignacion ?? null;
        $pasos = [self::paso('Enviada', 'hecho', $solicitud->fecha_solicitud)];

        if ($tipo === 'candidatura') {
            $evaluacion = collect($detalle->evaluaciones ?? [])->sortBy('fecha')->first();
            if ($evaluacion) {
                $pasos[] = self::paso('Evaluada por la empresa', 'hecho', $evaluacion->fecha);
            }
            if (isset($historial['preseleccionar_candidatura'])) {
                $pasos[] = self::paso('Preseleccionada', 'hecho', $historial['preseleccionar_candidatura']);
            }
        }

        if ($estado === 'cancelada') {
            $pasos[] = self::paso('Cancelada', 'detenido', $historial['cancelar_candidatura'] ?? $historial['cancelar_solicitud_direccion'] ?? null);

            return $pasos;
        }
        if ($estado === 'rechazada') {
            $pasos[] = self::paso('Rechazada', 'detenido', $decision->fecha ?? null);

            return $pasos;
        }
        if ($estado === 'aprobada') {
            $pasos[] = self::paso('Aprobada por la coordinación', 'hecho', $decision->fecha ?? null);
            $final = $tipo === 'candidatura' ? 'Participando en el proyecto' : 'Dirigiendo el proyecto';
            if ($asignacion && $asignacion->estado !== 'vigente') {
                $pasos[] = self::paso($final, 'hecho', $asignacion->inicio);
                $pasos[] = self::paso($asignacion->estado === 'finalizada' ? 'Participación concluida' : 'Retirada del proyecto',
                    $asignacion->estado === 'finalizada' ? 'hecho' : 'detenido', $asignacion->fin);
            } else {
                $pasos[] = self::paso($final, $asignacion ? 'actual' : 'pendiente', $asignacion->inicio ?? null);
            }

            return $pasos;
        }

        // Activa: los pasos que faltan, con el siguiente marcado como actual.
        $restantes = $tipo === 'candidatura'
            ? array_slice(['Evaluada por la empresa', 'Preseleccionada', 'Aprobada por la coordinación'], count($pasos) - 1)
            : ['Aprobada por la coordinación'];
        foreach ($restantes as $i => $etiqueta) {
            $pasos[] = self::paso($etiqueta, $i === 0 ? 'actual' : 'pendiente', null);
        }

        return $pasos;
    }

    /**
     * @param  iterable<object>  $revisiones  con fecha_envio y decision (opcional)
     * @param  iterable<object>  $historial  eventos de ciclo con operacion y fecha (opcional)
     * @return list<array{etiqueta:string,estado:string,fecha:?string}>
     */
    public static function proyecto(string $estado, iterable $revisiones = [], iterable $historial = []): array
    {
        $revisiones = collect($revisiones)->sortBy('fecha_envio');
        $envio = $revisiones->first()?->fecha_envio;
        $aprobada = $revisiones->first(fn ($r) => ($r->decision->resultado ?? null) === 'aprobada')?->decision->fecha;
        $ultimaDecision = $revisiones->last()?->decision->fecha ?? null;
        $ciclo = self::porOperacion($historial);
        $orden = ['borrador', 'en_revision', 'publicado', 'en_curso', 'finalizado'];
        $pasos = [
            ['Borrador', null], ['Enviado a revisión', $envio], ['Publicado en el catálogo', $aprobada],
            ['En curso', $ciclo['iniciar_proyecto'] ?? null], ['Finalizado', $ciclo['finalizar_proyecto'] ?? null],
        ];
        // Estados fuera de la secuencia principal: se insertan tras los pasos ya cumplidos.
        $especial = match ($estado) {
            'en_correccion' => [2, self::paso('Devuelto para corrección', 'actual', $ultimaDecision), true],
            'rechazado' => [2, self::paso('Rechazado', 'detenido', $ultimaDecision), false],
            'pausado' => [4, self::paso('En pausa', 'actual', $ciclo['pausar_proyecto'] ?? null), true],
            default => null,
        };
        if ($especial) {
            [$hechos, $insertado, $continua] = $especial;
            $salida = [];
            foreach ($pasos as $i => [$etiqueta, $fecha]) {
                if ($i === $hechos) {
                    $salida[] = $insertado;
                    if (! $continua) {
                        break;
                    }
                }
                $salida[] = self::paso($etiqueta, $i < $hechos ? 'hecho' : 'pendiente', $i < $hechos ? $fecha : null);
            }

            return $salida;
        }
        $posicion = array_search($estado, $orden, true);

        if ($estado === 'cancelado') {
            // Se canceló en algún punto del ciclo; se muestran los pasos alcanzados con fecha y el cierre.
            $salida = [self::paso('Borrador', 'hecho', null)];
            foreach (array_slice($pasos, 1, 3) as [$etiqueta, $fecha]) {
                if ($fecha) {
                    $salida[] = self::paso($etiqueta, 'hecho', $fecha);
                }
            }
            $salida[] = self::paso('Cancelado', 'detenido', $ciclo['cancelar_proyecto'] ?? null);

            return $salida;
        }

        $salida = [];
        foreach ($pasos as $i => [$etiqueta, $fecha]) {
            if ($i < $posicion || ($i === $posicion && $estado === 'finalizado')) {
                $salida[] = self::paso($etiqueta, 'hecho', $fecha);
            } elseif ($i === $posicion) {
                $salida[] = self::paso($etiqueta, 'actual', $fecha);
            } else {
                $salida[] = self::paso($etiqueta, 'pendiente', null);
            }
        }

        return $salida;
    }

    /** Fecha más reciente de cada operación del historial. */
    private static function porOperacion(iterable $historial): array
    {
        $fechas = [];
        foreach ($historial as $evento) {
            $op = $evento->operacion ?? null;
            if ($op && (! isset($fechas[$op]) || $evento->fecha > $fechas[$op])) {
                $fechas[$op] = $evento->fecha;
            }
        }

        return $fechas;
    }

    private static function paso(string $etiqueta, string $estado, ?string $fecha): array
    {
        return ['etiqueta' => $etiqueta, 'estado' => $estado, 'fecha' => $fecha];
    }
}
