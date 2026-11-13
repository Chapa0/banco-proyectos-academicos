<?php

namespace Tests\Feature;

use App\Support\Regreso;
use Illuminate\Http\Request;
use Tests\TestCase;

class RegresoTest extends TestCase
{
    private function peticion(string $url): Request
    {
        return Request::create($url, 'GET');
    }

    public function test_el_enlace_lleva_la_pagina_actual_con_sus_filtros(): void
    {
        $url = Regreso::enlace('/seguimiento/proyectos/5', $this->peticion('/participacion/direccion?buscar=pedidos&page=2'));

        $this->assertSame('/seguimiento/proyectos/5?volver='.rawurlencode('/participacion/direccion?buscar=pedidos&page=2'), $url);
        $this->assertSame('/perfil?volver=%2Fcatalogo%2F3#habilidades', Regreso::enlace('/perfil#habilidades', $this->peticion('/catalogo/3')));
    }

    public function test_volver_regresa_a_la_solicitud_de_origen_con_texto_acorde(): void
    {
        $destino = Regreso::destino('/seguimiento/proyectos', 'Volver al seguimiento',
            $this->peticion('/seguimiento/proyectos/5?volver='.rawurlencode('/participacion/direccion/3')));

        $this->assertSame(url('/participacion/direccion/3'), $destino['url']);
        $this->assertSame('Volver a la solicitud de dirección', $destino['etiqueta']);
    }

    public function test_la_cadena_de_regresos_se_conserva(): void
    {
        $lista = '/participacion/candidatura?buscar=inventario';
        $solicitud = '/participacion/candidatura/8?volver='.rawurlencode($lista);
        $proyecto = $this->peticion('/seguimiento/proyectos/5?volver='.rawurlencode($solicitud));
        $this->assertSame(url($solicitud), Regreso::destino('/x', 'x', $proyecto)['url']);

        $alRegresar = Regreso::destino('/x', 'x', $this->peticion($solicitud));
        $this->assertSame(url($lista), $alRegresar['url']);
        $this->assertSame('Volver a candidaturas', $alRegresar['etiqueta']);
    }

    public function test_sin_origen_o_con_origen_no_valido_usa_la_lista_de_la_seccion(): void
    {
        foreach (['', 'https://ejemplo.com/', '//ejemplo.com/panel', '/\\ejemplo.com', 'panel', '/no-existe', '/login', '/reportes/carga/exportar'] as $valor) {
            $destino = Regreso::destino('/catalogo', 'Volver al catálogo', $this->peticion('/catalogo/1?volver='.rawurlencode($valor)));
            $this->assertSame(['url' => '/catalogo', 'etiqueta' => 'Volver al catálogo'], $destino, $valor);
        }
        $this->assertSame('/catalogo', Regreso::destino('/catalogo', 'Volver al catálogo', $this->peticion('/catalogo/1'))['url']);
    }

    public function test_tras_enviar_un_formulario_se_recupera_el_origen_de_la_misma_pagina(): void
    {
        $peticion = $this->peticion('/perfil');
        $peticion->setLaravelSession($sesion = $this->app['session']->driver());
        $sesion->setPreviousUrl('http://localhost/perfil?volver='.rawurlencode('/catalogo/3'));
        $this->assertSame(url('/catalogo/3'), Regreso::destino('/panel', 'Volver a mi espacio', $peticion)['url']);

        $sesion->setPreviousUrl('http://localhost/avisos?volver='.rawurlencode('/catalogo/3'));
        $this->assertSame('/panel', Regreso::destino('/panel', 'Volver a mi espacio', $peticion)['url']);
    }

    public function test_un_origen_demasiado_largo_conserva_los_filtros_y_descarta_la_cadena(): void
    {
        $peticion = $this->peticion('/catalogo?buscar=web&volver='.rawurlencode('/panel?x='.str_repeat('a', 1600)));

        $this->assertSame('/catalogo/2?volver='.rawurlencode('/catalogo?buscar=web'), Regreso::enlace('/catalogo/2', $peticion));
    }
}
