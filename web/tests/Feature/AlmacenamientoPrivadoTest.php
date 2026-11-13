<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class AlmacenamientoPrivadoTest extends TestCase
{
    private function enlaceFirmado(string $ruta, bool $subida = false): string
    {
        $parametros = ['expires' => now()->addMinutes(5)->timestamp];
        if ($subida) {
            $parametros['upload'] = 'true';
        }
        $uri = '/storage/'.$ruta.'?'.http_build_query($parametros);

        return $uri.'&signature='.hash_hmac('sha256', $uri, config('app.key'));
    }

    public function test_un_enlace_firmado_no_sustituye_el_permiso_de_descarga(): void
    {
        Storage::fake('local');
        $ruta = 'documentos/11111111-1111-4111-8111-111111111111.pdf';
        Storage::disk('local')->put($ruta, '%PDF-1.4 archivo privado');

        $this->get($this->enlaceFirmado($ruta))->assertNotFound();
    }

    public function test_un_enlace_firmado_no_permite_sobrescribir_un_archivo_privado(): void
    {
        Storage::fake('local');
        $ruta = 'documentos/11111111-1111-4111-8111-111111111111.pdf';
        $original = '%PDF-1.4 archivo privado';
        Storage::disk('local')->put($ruta, $original);

        $this->call('PUT', $this->enlaceFirmado($ruta, true), content: 'Contenido ajeno')->assertNotFound();
        $this->assertSame($original, Storage::disk('local')->get($ruta));
    }
}
