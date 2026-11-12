<?php

namespace Tests\Unit;

use App\Services\CoincidenciaService;
use PHPUnit\Framework\TestCase;

class CoincidenciaServiceTest extends TestCase
{
    private function habilidad(int $id, string $nombre = '', bool $obligatoria = false): object
    {
        return (object) ['habilidad_id' => $id, 'nombre' => $nombre, 'obligatoria' => $obligatoria];
    }

    public function test_cuenta_cumplidas_y_ordena_faltantes_obligatorias_primero(): void
    {
        $resultado = (new CoincidenciaService)->calcular(
            [$this->habilidad(1, 'Python'), $this->habilidad(2, 'SQL', true), $this->habilidad(3, 'Comunicación'), $this->habilidad(4, 'Git', true)],
            [$this->habilidad(3)],
        );

        $this->assertSame(4, $resultado->requeridas);
        $this->assertSame(1, $resultado->cumplidas);
        $this->assertSame(2, $resultado->faltan_obligatorias);
        $this->assertSame(['Git', 'SQL', 'Python'], array_map(fn ($f) => $f->nombre, $resultado->faltantes));
        $this->assertSame('baja', $resultado->nivel);
    }

    public function test_proyecto_sin_habilidades_no_produce_coincidencia(): void
    {
        $this->assertNull((new CoincidenciaService)->calcular([], [$this->habilidad(1)]));
    }

    public function test_coincidencia_completa_y_parcial(): void
    {
        $servicio = new CoincidenciaService;
        $this->assertSame('completa', $servicio->calcular([$this->habilidad(1, 'A')], [$this->habilidad(1)])->nivel);
        $this->assertSame('parcial', $servicio->calcular([$this->habilidad(1, 'A'), $this->habilidad(2, 'B')], [$this->habilidad(2)])->nivel);
    }
}
