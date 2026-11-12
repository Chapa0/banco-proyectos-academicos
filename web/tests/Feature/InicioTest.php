<?php

namespace Tests\Feature;

use Tests\TestCase;

class InicioTest extends TestCase
{
    public function test_la_portada_se_renderiza_sin_consultar_datos_privados(): void
    {
        // La conexión de pruebas es deliberadamente inexistente. Esta página
        // pública debe funcionar sin consultar usuarios o proyectos internos.
        $this->get('/')
            ->assertOk()
            ->assertSee('Banco de proyectos')
            ->assertDontSee('proweb_admin')
            ->assertDontSee('hash_contrasena');
    }

    public function test_no_se_habilitaron_rutas_de_acceso_o_api_anticipadas(): void
    {
        $this->get('/login')->assertOk();
        $this->get('/register')->assertNotFound();
        $this->get('/api/proyectos')->assertNotFound();
    }
}
