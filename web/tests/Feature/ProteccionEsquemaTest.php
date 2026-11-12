<?php

namespace Tests\Feature;

use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Facades\Artisan;
use RuntimeException;
use Tests\TestCase;

class ProteccionEsquemaTest extends TestCase
{
    public function test_artisan_no_puede_recrear_o_vaciar_la_base_existente(): void
    {
        // Laravel desactiva el puente de eventos de consola al ejecutar tests.
        // Lo activamos igual que en el arranque normal de Artisan.
        $this->app->make(Kernel::class)->rerouteSymfonyCommandEvents();
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('migraciones SQL');

        // Se rechaza antes de conectar a la base inexistente de las pruebas.
        Artisan::call('migrate:fresh', ['--force' => true]);
    }
}
