<?php

namespace Tests\Unit;

use App\Support\LineaTiempo;
use PHPUnit\Framework\TestCase;

class LineaTiempoTest extends TestCase
{
    private function participacion(string $estado, array $extra = []): object
    {
        return (object) array_merge([
            'solicitud' => (object) ['estado' => $estado, 'fecha_solicitud' => '2026-11-01T10:00:00Z'],
            'evaluaciones' => [], 'decisiones' => [], 'historial' => [], 'asignacion' => null,
        ], $extra);
    }

    private function resumen(array $pasos): array
    {
        return array_map(fn ($p) => $p['etiqueta'].':'.$p['estado'], $pasos);
    }

    public function test_candidatura_recien_enviada_marca_la_evaluacion_como_paso_actual(): void
    {
        $this->assertSame(['Enviada:hecho', 'Evaluada por la empresa:actual', 'Preseleccionada:pendiente', 'Aprobada por la coordinación:pendiente'],
            $this->resumen(LineaTiempo::participacion('candidatura', $this->participacion('pendiente_evaluacion'))));
    }

    public function test_candidatura_preseleccionada_usa_fechas_de_evaluacion_e_historial(): void
    {
        $pasos = LineaTiempo::participacion('candidatura', $this->participacion('preseleccionada', [
            'evaluaciones' => [(object) ['fecha' => '2026-11-03T10:00:00Z'], (object) ['fecha' => '2026-11-02T10:00:00Z']],
            'historial' => [(object) ['operacion' => 'preseleccionar_candidatura', 'fecha' => '2026-11-04T10:00:00Z']],
        ]));
        $this->assertSame(['Enviada:hecho', 'Evaluada por la empresa:hecho', 'Preseleccionada:hecho', 'Aprobada por la coordinación:actual'], $this->resumen($pasos));
        $this->assertSame('2026-11-02T10:00:00Z', $pasos[1]['fecha'], 'Primera evaluación');
        $this->assertSame('2026-11-04T10:00:00Z', $pasos[2]['fecha']);
    }

    public function test_candidatura_rechazada_termina_en_el_rechazo(): void
    {
        $pasos = LineaTiempo::participacion('candidatura', $this->participacion('rechazada', [
            'evaluaciones' => [(object) ['fecha' => '2026-11-02T10:00:00Z']],
            'decisiones' => [(object) ['fecha' => '2026-11-05T10:00:00Z', 'resultado' => 'rechazada']],
        ]));
        $this->assertSame(['Enviada:hecho', 'Evaluada por la empresa:hecho', 'Rechazada:detenido'], $this->resumen($pasos));
        $this->assertSame('2026-11-05T10:00:00Z', $pasos[2]['fecha']);
    }

    public function test_aprobada_con_asignacion_vigente_y_finalizada(): void
    {
        $vigente = $this->participacion('aprobada', ['asignacion' => (object) ['estado' => 'vigente', 'inicio' => '2026-11-06T10:00:00Z', 'fin' => null]]);
        $this->assertSame(['Enviada:hecho', 'Aprobada por la coordinación:hecho', 'Participando en el proyecto:actual'],
            $this->resumen(LineaTiempo::participacion('candidatura', $vigente)));
        $finalizada = $this->participacion('aprobada', ['asignacion' => (object) ['estado' => 'finalizada', 'inicio' => '2026-11-06T10:00:00Z', 'fin' => '2026-12-01T10:00:00Z']]);
        $this->assertSame(['Enviada:hecho', 'Aprobada por la coordinación:hecho', 'Dirigiendo el proyecto:hecho', 'Participación concluida:hecho'],
            $this->resumen(LineaTiempo::participacion('direccion', $finalizada)));
    }

    public function test_solicitud_cancelada(): void
    {
        $pasos = LineaTiempo::participacion('direccion', $this->participacion('cancelada', [
            'historial' => [(object) ['operacion' => 'cancelar_solicitud_direccion', 'fecha' => '2026-11-02T10:00:00Z']],
        ]));
        $this->assertSame(['Enviada:hecho', 'Cancelada:detenido'], $this->resumen($pasos));
        $this->assertSame('2026-11-02T10:00:00Z', $pasos[1]['fecha']);
    }

    public function test_proyecto_en_cada_estado(): void
    {
        $revisiones = [
            (object) ['fecha_envio' => '2026-10-01T10:00:00Z', 'decision' => (object) ['resultado' => 'en_correccion', 'fecha' => '2026-10-02T10:00:00Z']],
            (object) ['fecha_envio' => '2026-10-05T10:00:00Z', 'decision' => (object) ['resultado' => 'aprobada', 'fecha' => '2026-10-06T10:00:00Z']],
        ];
        $base = ['Borrador', 'Enviado a revisión', 'Publicado en el catálogo', 'En curso', 'Finalizado'];
        $this->assertSame(['Borrador:actual', 'Enviado a revisión:pendiente', 'Publicado en el catálogo:pendiente', 'En curso:pendiente', 'Finalizado:pendiente'],
            $this->resumen(LineaTiempo::proyecto('borrador')));
        $publicado = LineaTiempo::proyecto('publicado', $revisiones);
        $this->assertSame(['Borrador:hecho', 'Enviado a revisión:hecho', 'Publicado en el catálogo:actual', 'En curso:pendiente', 'Finalizado:pendiente'], $this->resumen($publicado));
        $this->assertSame(['2026-10-01T10:00:00Z', '2026-10-06T10:00:00Z'], [$publicado[1]['fecha'], $publicado[2]['fecha']]);
        $this->assertSame(['Borrador:hecho', 'Enviado a revisión:hecho', 'Devuelto para corrección:actual', 'Publicado en el catálogo:pendiente', 'En curso:pendiente', 'Finalizado:pendiente'],
            $this->resumen(LineaTiempo::proyecto('en_correccion', [$revisiones[0]])));
        $this->assertSame(['Borrador:hecho', 'Enviado a revisión:hecho', 'Rechazado:detenido'], $this->resumen(LineaTiempo::proyecto('rechazado', [$revisiones[0]])));
        $ciclo = [(object) ['operacion' => 'iniciar_proyecto', 'fecha' => '2026-11-01T10:00:00Z'], (object) ['operacion' => 'pausar_proyecto', 'fecha' => '2026-11-10T10:00:00Z']];
        $this->assertSame(['Borrador:hecho', 'Enviado a revisión:hecho', 'Publicado en el catálogo:hecho', 'En curso:hecho', 'En pausa:actual', 'Finalizado:pendiente'],
            $this->resumen(LineaTiempo::proyecto('pausado', $revisiones, $ciclo)));
        $fin = LineaTiempo::proyecto('finalizado', $revisiones, [(object) ['operacion' => 'finalizar_proyecto', 'fecha' => '2026-12-01T10:00:00Z']]);
        $this->assertSame(array_map(fn ($e) => $e.':hecho', $base), $this->resumen($fin));
        $this->assertSame(['Borrador:hecho', 'Enviado a revisión:hecho', 'Publicado en el catálogo:hecho', 'Cancelado:detenido'],
            $this->resumen(LineaTiempo::proyecto('cancelado', $revisiones, [(object) ['operacion' => 'cancelar_proyecto', 'fecha' => '2026-11-02T10:00:00Z']])));
    }
}
