<?php

namespace Tests\Integration;

use App\Http\Controllers\ReporteController;
use Illuminate\Foundation\Http\Middleware\PreventRequestForgery;
use Illuminate\Http\UploadedFile;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\PostgresTestCase;
use Throwable;

class CsrfActivoEnAvisos extends PreventRequestForgery
{
    protected function runningUnitTests()
    {
        return false;
    }
}

class AvisosReportesTest extends PostgresTestCase
{
    private const PASSWORD = 'PruebaSegura-2026!';

    private ?string $cuenta = null;

    protected function setUp(): void
    {
        parent::setUp();
        if (! getenv('BANCO_TEST_WEB07')) {
            $this->markTestSkipped('Ejecuta python tests/comunicacion.py para la integración WEB-07.');
        }
    }

    public function call($method, $uri, $parameters = [], $cookies = [], $files = [], $server = [], $content = null)
    {
        $conexion = DB::connection('pgsql');
        $nivel = $conexion->transactionLevel();
        if ($nivel === 0) {
            return parent::call($method, $uri, $parameters, $cookies, $files, $server, $content);
        }
        $conexion->beginTransaction();
        try {
            $respuesta = parent::call($method, $uri, $parameters, $cookies, $files, $server, $content);
            if ($respuesta->getStatusCode() >= 400) {
                $conexion->rollBack($nivel);
            } else {
                $conexion->commit();
            }

            return $respuesta;
        } catch (Throwable $error) {
            $conexion->rollBack($nivel);
            throw $error;
        }
    }

    private function entrar(string $cuenta = 'alumno'): void
    {
        if ($this->cuenta !== null) {
            $this->post('/logout')->assertRedirect('/login');
        }
        $correo = str_contains($cuenta, '@') ? $cuenta : 'web02-'.$cuenta.'@example.invalid';
        $this->post('/login', ['correo' => $correo, 'password' => self::PASSWORD])->assertRedirect('/panel');
        $this->cuenta = $correo;
    }

    private function bandeja(array $filtros = []): object
    {
        $respuesta = $this->get('/avisos'.($filtros ? '?'.http_build_query($filtros) : ''))->assertOk();
        $avisos = $respuesta->viewData('avisos');
        $this->assertInstanceOf(LengthAwarePaginator::class, $avisos);

        return (object) ['avisos' => $avisos, 'noLeidos' => $respuesta->viewData('noLeidos')];
    }

    private function reporte(string $tipo = 'proyectos', array $filtros = []): object
    {
        $respuesta = $this->get('/reportes/'.$tipo.($filtros ? '?'.http_build_query($filtros) : ''))->assertOk();
        $filas = $respuesta->viewData('filas');
        $this->assertInstanceOf(LengthAwarePaginator::class, $filas);

        return (object) ['filas' => $filas, 'resumen' => $respuesta->viewData('resumen'),
            'opciones' => $respuesta->viewData('opciones')];
    }

    private function resumen(object $actual, array $esperado): void
    {
        foreach ($esperado as $clave => $valor) {
            $this->assertSame($valor, (int) $actual->$clave, $clave);
        }
    }

    public static function roles(): array
    {
        return ['administrador' => ['admin'], 'empresa' => ['empresa'], 'alumno' => ['alumno'], 'profesor' => ['profesor']];
    }

    #[DataProvider('roles')]
    public function test_cada_rol_activo_consulta_su_bandeja_y_su_detalle(string $rol): void
    {
        $this->entrar($rol);
        $bandeja = $this->bandeja();
        $this->assertGreaterThan(0, $bandeja->avisos->total());
        $this->assertGreaterThan(0, $bandeja->noLeidos);
        foreach ($bandeja->avisos as $aviso) {
            $this->assertEqualsCanonicalizing(['id', 'mensaje', 'fecha', 'fecha_lectura'], array_keys((array) $aviso));
        }
        $primero = $bandeja->avisos->items()[0];
        $detalle = $this->get('/avisos/'.$primero->id)->assertOk()->viewData('aviso');
        $this->assertSame((int) $primero->id, (int) $detalle->id);
        $this->assertSame($primero->mensaje, $detalle->mensaje);
        $this->assertNull($detalle->fecha_lectura);
        $this->assertSame($bandeja->noLeidos, $this->bandeja()->noLeidos);
    }

    public function test_paginacion_filtros_y_contador_de_avisos_independiente_del_filtro(): void
    {
        $this->entrar();
        $primera = $this->bandeja();
        $segunda = $this->bandeja(['page' => 2]);
        $this->assertSame(27, $primera->avisos->total());
        $this->assertCount(20, $primera->avisos);
        $this->assertCount(7, $segunda->avisos);
        $this->assertEmpty(array_intersect(array_column($primera->avisos->items(), 'id'), array_column($segunda->avisos->items(), 'id')));
        $busqueda = $this->bandeja(['buscar' => 'AVISO_XSS_WEB07']);
        $this->assertSame(1, $busqueda->avisos->total());
        $this->assertSame(27, $busqueda->noLeidos);
        $this->assertSame(0, $this->bandeja(['estado' => 'leidos'])->avisos->total());
        $this->assertSame(27, $this->bandeja(['estado' => 'no_leidos'])->avisos->total());
        $this->assertSame(0, $this->bandeja(['buscar' => 'TEXTO_INEXISTENTE_WEB07'])->avisos->total());
    }

    public function test_pagina_de_avisos_fuera_de_rango_conserva_resultados_y_filtros_para_volver(): void
    {
        $this->entrar();
        $filtros = ['page' => 999, 'buscar' => 'AVISO_XSS_WEB07', 'estado' => 'no_leidos'];
        $respuesta = $this->get('/avisos?'.http_build_query($filtros))->assertOk()
            ->assertSee('No hay avisos en esta página.')->assertDontSee('No hay avisos con esos filtros.');
        $pagina = $respuesta->viewData('avisos');
        $this->assertSame(1, $pagina->total());
        $this->assertCount(0, $pagina);
        $this->assertSame(999, $pagina->currentPage());
        $this->assertSame(27, $respuesta->viewData('noLeidos'));
        $primera = $pagina->url(1);
        $respuesta->assertSee('href="'.e($primera).'">Primera página</a>', false);
        parse_str(parse_url($primera, PHP_URL_QUERY), $consulta);
        $this->assertSame(['page' => '1', 'buscar' => $filtros['buscar'], 'estado' => $filtros['estado']], $consulta);
        $recuperada = $this->get($primera)->assertOk()->assertDontSee('No hay avisos en esta página.')->viewData('avisos');
        $this->assertSame(1, $recuperada->total());
        $this->assertCount(1, $recuperada);
        $vacia = $this->get('/avisos?buscar=TEXTO_INEXISTENTE_WEB07&page=999')->assertOk()
            ->assertSee('No hay avisos con esos filtros.')->assertDontSee('No hay avisos en esta página.');
        $this->assertSame(0, $vacia->viewData('avisos')->total());
    }

    public function test_lectura_solo_post_persistente_e_idempotente_sin_borrar_el_aviso(): void
    {
        $this->entrar();
        $ruta = '/avisos/-270501';
        $this->get($ruta)->assertOk();
        $this->get($ruta.'/leer')->assertStatus(405);
        $this->assertNull($this->get($ruta)->assertOk()->viewData('aviso')->fecha_lectura);
        $this->post($ruta.'/leer')->assertRedirect($ruta)->assertSessionHasNoErrors();
        $leido = $this->get($ruta)->assertOk()->viewData('aviso');
        $this->assertNotNull($leido->fecha_lectura);
        $this->post($ruta.'/leer')->assertRedirect($ruta)->assertSessionHasNoErrors();
        $this->assertSame($leido->fecha_lectura, $this->get($ruta)->assertOk()->viewData('aviso')->fecha_lectura);
        $this->entrar();
        $this->assertSame($leido->fecha_lectura, $this->get($ruta)->assertOk()->viewData('aviso')->fecha_lectura);
        $this->assertSame(26, $this->bandeja()->noLeidos);
        $this->assertSame(27, $this->bandeja()->avisos->total());
        $this->assertSame(1, $this->bandeja(['estado' => 'leidos'])->avisos->total());
        $this->assertSame(26, $this->bandeja(['estado' => 'no_leidos'])->avisos->total());
    }

    public function test_csrf_real_protege_lectura_y_admite_el_token_de_la_sesion(): void
    {
        $this->entrar();
        $this->app->bind(PreventRequestForgery::class, CsrfActivoEnAvisos::class);
        $this->post('/avisos/-270501/leer')->assertStatus(419);
        $this->assertNull($this->get('/avisos/-270501')->assertOk()->viewData('aviso')->fecha_lectura);
        $this->post('/avisos/-270501/leer', ['_token' => session()->token()])->assertRedirect('/avisos/-270501');
        $this->assertNotNull($this->get('/avisos/-270501')->assertOk()->viewData('aviso')->fecha_lectura);
    }

    public function test_privacidad_individual_incluso_frente_al_administrador(): void
    {
        $this->entrar('profesor');
        $propio = $this->bandeja()->avisos->items()[0];
        foreach (['alumno', 'empresa', 'admin'] as $ajeno) {
            $this->entrar($ajeno);
            $this->get('/avisos/'.$propio->id)->assertStatus(403);
            $this->post('/avisos/'.$propio->id.'/leer')->assertStatus(403);
            $this->assertNotContains($propio->id, array_column($this->bandeja()->avisos->items(), 'id'));
        }
        $this->entrar('profesor');
        $this->assertNull($this->get('/avisos/'.$propio->id)->assertOk()->viewData('aviso')->fecha_lectura);
    }

    public static function idsInvalidos(): array
    {
        return ['cero' => ['0'], 'texto' => ['ajeno'], 'fuera bigint' => ['9223372036854775808'], 'inexistente' => ['9223372036854775807']];
    }

    #[DataProvider('idsInvalidos')]
    public function test_identificadores_invalidos_no_consultan_ni_marcan(string $id): void
    {
        $this->entrar();
        $this->get('/avisos/'.$id)->assertNotFound();
        $this->post('/avisos/'.$id.'/leer')->assertNotFound();
        $this->assertSame(27, $this->bandeja()->noLeidos);
    }

    public static function camposReservados(): array
    {
        return array_combine($campos = ['actor', 'actor_usuario_id', 'usuario_id', 'destinatario_usuario_id',
            'id', 'aviso_id', 'notificacion_id', 'evento_id', 'fecha', 'fecha_lectura', 'mensaje', 'leido',
            'estado', 'rol', 'rol_principal', 'recurso', 'enlace'], array_map(fn ($campo) => [$campo], $campos));
    }

    #[DataProvider('camposReservados')]
    public function test_no_se_puede_falsificar_actor_destinatario_o_contenido_al_leer(string $campo): void
    {
        $this->entrar();
        $this->post('/avisos/-270501/leer', [$campo => 'alterado'])->assertRedirect()->assertSessionHasErrors($campo);
        $this->assertNull($this->get('/avisos/-270501')->assertOk()->viewData('aviso')->fecha_lectura);
    }

    public function test_lectura_no_admite_archivos(): void
    {
        $this->entrar();
        $this->post('/avisos/-270501/leer', ['archivo' => UploadedFile::fake()->create('aviso.pdf', 1)])
            ->assertRedirect()->assertSessionHasErrors('archivos');
        $this->assertNull($this->get('/avisos/-270501')->assertOk()->viewData('aviso')->fecha_lectura);
    }

    public function test_mensajes_escapados_y_sin_datos_privados_del_evento(): void
    {
        $this->entrar();
        $ataque = '<script>alert("AVISO_XSS_WEB07")</script>';
        $this->get('/avisos?buscar=AVISO_XSS_WEB07')->assertOk()->assertSee($ataque)->assertDontSee($ataque, false);
        $this->get('/avisos/-270501')->assertOk()->assertSee($ataque)->assertDontSee($ataque, false);
        foreach (['admin', 'empresa', 'alumno', 'profesor'] as $rol) {
            $this->entrar($rol);
            foreach ([1, 2] as $pagina) {
                $respuesta = $this->get('/avisos?page='.$pagina)->assertOk();
                foreach (['MOTIVO_', 'COMENTARIO_PRIVADO_WEB07', 'EXPERIENCIA_PRIVADA_WEB07',
                    'JUSTIFICACION_PRIVADA_WEB07', 'EMPLEADO_PRIVADO_WEB07', 'EVIDENCIA_PRIVADA_WEB07',
                    'hash_contrasena', 'web02-alumno@example.invalid', 'web02-profesor@example.invalid'] as $privado) {
                    $respuesta->assertDontSee($privado, false);
                }
            }
        }
    }

    public function test_enlace_al_detalle_autorizado_no_duplica_lectura(): void
    {
        $this->entrar('profesor');
        $aviso = $this->bandeja()->avisos->items()[0];
        $respuesta = $this->get('/avisos/'.$aviso->id)->assertOk();
        $enlace = $respuesta->viewData('enlace');
        $this->assertNotNull($enlace);
        $this->assertMatchesRegularExpression('~/participacion/direccion/-?\d+$~', $enlace['url']);
        $this->get($enlace['url'])->assertOk();
        $this->assertNull($this->get('/avisos/'.$aviso->id)->assertOk()->viewData('aviso')->fecha_lectura);
    }

    public function test_invitado_inactivo_y_clave_temporal_no_acceden_a_consultas(): void
    {
        foreach (['/avisos', '/avisos/-270501', '/reportes', '/reportes/asignaciones'] as $ruta) {
            $this->get($ruta)->assertRedirect('/login');
        }
        $this->post('/avisos/-270501/leer')->assertRedirect('/login');
        $this->post('/login', ['correo' => 'web02-inactivo@example.invalid', 'password' => self::PASSWORD])->assertSessionHasErrors('correo');
        $this->get('/avisos')->assertRedirect('/login');
        $this->post('/login', ['correo' => 'web02-temporal@example.invalid', 'password' => self::PASSWORD])->assertRedirect('/clave');
        $this->get('/avisos')->assertRedirect('/clave');
        $this->post('/avisos/-270501/leer')->assertRedirect('/clave');
        $this->get('/reportes')->assertRedirect('/clave');
    }

    public static function noAdministradores(): array
    {
        return ['alumno' => ['alumno'], 'profesor' => ['profesor'], 'empresa' => ['empresa']];
    }

    #[DataProvider('noAdministradores')]
    public function test_los_cinco_reportes_estan_restringidos_al_administrador(string $rol): void
    {
        $this->entrar($rol);
        foreach (['proyectos', 'candidaturas', 'direcciones', 'carga_profesores', 'asignaciones'] as $tipo) {
            $this->get('/reportes/'.$tipo)->assertForbidden();
        }
        $this->get('/reportes')->assertForbidden();
    }

    public function test_reporte_proyectos_totaliza_sin_multiplicar_por_solicitudes_o_evaluaciones(): void
    {
        $this->entrar('admin');
        $this->get('/reportes')->assertOk()->assertViewHas('tipo', 'proyectos');
        $primera = $this->reporte('proyectos', ['buscar' => 'Proyecto WEB07']);
        $segunda = $this->reporte('proyectos', ['buscar' => 'Proyecto WEB07', 'page' => 2]);
        $this->assertSame(26, $primera->filas->total());
        $this->assertCount(20, $primera->filas);
        $this->assertCount(6, $segunda->filas);
        $this->assertEmpty(array_intersect(array_column($primera->filas->items(), 'id'), array_column($segunda->filas->items(), 'id')));
        $this->resumen($primera->resumen, ['registros' => 26, 'alumnos_vigentes' => 5, 'directores_vigentes' => 3]);
        $this->assertEquals($primera->resumen, $segunda->resumen);
        $this->assertSame(19, $this->reporte('proyectos', ['buscar' => 'Proyecto WEB07', 'estado' => 'publicado'])->filas->total());
        $this->assertSame(5, $this->reporte('proyectos', ['buscar' => 'Proyecto WEB07', 'empresa_id' => -220102])->filas->total());
        $unico = $this->reporte('proyectos', ['buscar' => 'Proyecto WEB07', 'estado' => 'en_curso', 'empresa_id' => -220101]);
        $this->assertSame(1, $unico->filas->total());
        $this->resumen($unico->resumen, ['registros' => 1, 'alumnos_vigentes' => 2, 'directores_vigentes' => 1]);
    }

    public function test_pagina_de_reporte_fuera_de_rango_conserva_totales_tipo_y_filtros_para_volver(): void
    {
        $this->entrar('admin');
        $filtros = ['page' => 999, 'buscar' => 'Proyecto WEB07', 'estado' => 'publicado', 'empresa_id' => -220102];
        $respuesta = $this->get('/reportes/proyectos?'.http_build_query($filtros))->assertOk()
            ->assertSee('No hay registros en esta página.')->assertDontSee('No hay registros con esos filtros.');
        $pagina = $respuesta->viewData('filas');
        $this->assertSame(5, $pagina->total());
        $this->assertCount(0, $pagina);
        $this->assertSame(999, $pagina->currentPage());
        $this->resumen($respuesta->viewData('resumen'), ['registros' => 5, 'alumnos_vigentes' => 0, 'directores_vigentes' => 0]);
        $primera = $pagina->url(1);
        $respuesta->assertSee('href="'.e($primera).'">Primera página</a>', false);
        $this->assertSame('/reportes/proyectos', parse_url($primera, PHP_URL_PATH));
        parse_str(parse_url($primera, PHP_URL_QUERY), $consulta);
        $this->assertSame(['page' => '1', 'buscar' => $filtros['buscar'], 'estado' => $filtros['estado'], 'empresa_id' => '-220102'], $consulta);
        $recuperada = $this->get($primera)->assertOk()->assertDontSee('No hay registros en esta página.');
        $this->assertSame(5, $recuperada->viewData('filas')->total());
        $this->assertCount(5, $recuperada->viewData('filas'));
        $this->assertEquals($respuesta->viewData('resumen'), $recuperada->viewData('resumen'));
        $vacia = $this->get('/reportes/proyectos?buscar=TEXTO_INEXISTENTE_WEB07&page=999')->assertOk()
            ->assertSee('No hay registros con esos filtros.')->assertDontSee('No hay registros en esta página.');
        $this->assertSame(0, $vacia->viewData('filas')->total());
    }

    public function test_reporte_candidaturas_cuenta_solicitudes_y_estados_no_las_22_evaluaciones(): void
    {
        $this->entrar('admin');
        $datos = $this->reporte('candidaturas', ['buscar' => 'Proyecto WEB07']);
        $this->assertSame(10, $datos->filas->total());
        $this->resumen($datos->resumen, ['registros' => 10, 'activas' => 3, 'aprobadas' => 6, 'rechazadas' => 1, 'canceladas' => 0]);
        $this->assertSame(3, $this->reporte('candidaturas', ['proyecto_id' => -270202])->filas->total());
        $this->assertSame(1, $this->reporte('candidaturas', ['buscar' => 'Proyecto WEB07', 'empresa_id' => -220102])->filas->total());
        $this->assertSame(1, $this->reporte('candidaturas', ['buscar' => 'Proyecto WEB07', 'estado' => 'evaluada'])->filas->total());
    }

    public function test_reporte_direcciones_aplica_profesor_proyecto_empresa_y_estado(): void
    {
        $this->entrar('admin');
        $datos = $this->reporte('direcciones', ['buscar' => 'Proyecto WEB07']);
        $this->assertSame(7, $datos->filas->total());
        $this->resumen($datos->resumen, ['registros' => 7, 'pendientes' => 1, 'aprobadas' => 5, 'rechazadas' => 1, 'canceladas' => 0]);
        $this->assertSame(2, $this->reporte('direcciones', ['buscar' => 'Proyecto WEB07', 'profesor_id' => -270011, 'estado' => 'aprobada'])->filas->total());
        $this->assertSame(1, $this->reporte('direcciones', ['empresa_id' => -220102, 'proyecto_id' => -270226, 'estado' => 'pendiente'])->filas->total());
    }

    public function test_carga_incluye_profesores_sin_asignacion_y_cuenta_inactiva_sin_liberar_carga(): void
    {
        $this->entrar('admin');
        $datos = $this->reporte('carga_profesores', ['buscar' => 'Profesor WEB07']);
        $this->assertSame(4, $datos->filas->total());
        $this->resumen($datos->resumen, ['registros' => 4, 'proyectos_vigentes' => 3, 'profesores_con_carga' => 2]);
        $cargas = [];
        foreach ($datos->filas as $fila) {
            $cargas[(int) $fila->profesor_id] = (int) $fila->proyectos_vigentes;
            $this->assertSame(3, (int) $fila->limite_proyectos);
        }
        $this->assertEquals([-270011 => 2, -270012 => 0, -270013 => 1, -270014 => 0], $cargas);
        $filtrado = $this->reporte('carga_profesores', ['profesor_id' => -270013]);
        $this->assertSame(1, $filtrado->filas->total());
        $this->resumen($filtrado->resumen, ['registros' => 1, 'proyectos_vigentes' => 1, 'profesores_con_carga' => 1]);
    }

    public function test_reporte_asignaciones_distingue_vigentes_finalizadas_y_retiros(): void
    {
        $this->entrar('admin');
        $datos = $this->reporte('asignaciones', ['buscar' => 'Proyecto WEB07']);
        $this->assertSame(11, $datos->filas->total());
        $this->resumen($datos->resumen, ['registros' => 11, 'alumnos_vigentes' => 5, 'directores_vigentes' => 3, 'finalizadas' => 2, 'revocadas' => 1]);
        $vigentes = $this->reporte('asignaciones', ['buscar' => 'Proyecto WEB07', 'estado' => 'vigente']);
        $this->assertSame(8, $vigentes->filas->total());
        $this->resumen($vigentes->resumen, ['registros' => 8, 'alumnos_vigentes' => 5, 'directores_vigentes' => 3, 'finalizadas' => 0, 'revocadas' => 0]);
        $this->assertSame(3, $this->reporte('asignaciones', ['empresa_id' => -220101, 'proyecto_id' => -270201])->filas->total());
        $this->assertSame(2, $this->reporte('asignaciones', ['buscar' => 'Proyecto WEB07', 'estado' => 'finalizada'])->filas->total());
        $this->assertSame(1, $this->reporte('asignaciones', ['buscar' => 'Proyecto WEB07', 'estado' => 'revocada'])->filas->total());
    }

    public function test_reportes_devuelven_campos_explicitos_y_vacios_sin_filtrar_datos_privados(): void
    {
        $this->entrar('admin');
        $campos = [
            'proyectos' => ['id', 'titulo', 'estado', 'empresa_id', 'razon_social', 'cupo_maximo_alumnos', 'alumnos_vigentes', 'directores_vigentes'],
            'candidaturas' => ['id', 'proyecto_id', 'titulo', 'razon_social', 'solicitante_nombre', 'estado', 'fecha_solicitud'],
            'direcciones' => ['id', 'proyecto_id', 'titulo', 'razon_social', 'solicitante_nombre', 'estado', 'fecha_solicitud'],
            'carga_profesores' => ['profesor_id', 'nombre', 'proyectos_vigentes', 'limite_proyectos'],
            'asignaciones' => ['id', 'tipo', 'solicitud_id', 'proyecto_id', 'titulo', 'razon_social', 'participante_nombre', 'estado', 'inicio', 'fin'],
        ];
        foreach ($campos as $tipo => $permitidos) {
            $datos = $this->reporte($tipo, ['buscar' => $tipo === 'carga_profesores' ? 'Profesor WEB07' : 'Proyecto WEB07']);
            foreach ($datos->filas as $fila) {
                $this->assertEqualsCanonicalizing($permitidos, array_keys((array) $fila));
            }
            foreach (['empresas' => ['id', 'razon_social'], 'proyectos' => ['id', 'titulo'], 'profesores' => ['id', 'nombre']] as $opcion => $columnas) {
                foreach ($datos->opciones->$opcion as $fila) {
                    $this->assertEqualsCanonicalizing($columnas, array_keys((array) $fila));
                }
            }
            $vacio = $this->reporte($tipo, ['buscar' => 'TEXTO_INEXISTENTE_WEB07']);
            $this->assertSame(0, $vacio->filas->total());
            foreach ((array) $vacio->resumen as $valor) {
                $this->assertSame(0, (int) $valor);
            }
            $html = $this->get('/reportes/'.$tipo.'?buscar=WEB07')->assertOk();
            foreach (['MOTIVO_', 'COMENTARIO_PRIVADO_WEB07', 'EMPLEADO_PRIVADO_WEB07', 'EVIDENCIA_PRIVADA_WEB07', 'hash_contrasena', 'web07-profesor-3@example.invalid'] as $privado) {
                $html->assertDontSee($privado, false);
            }
        }
        $ataque = '<script>alert("XSS_WEB07")</script>';
        $this->get('/reportes/proyectos?buscar=Proyecto+WEB07+26')->assertOk()->assertSee($ataque)->assertDontSee($ataque, false);
        $this->get('/reportes/desconocido')->assertNotFound();
        $this->post('/reportes/proyectos')->assertStatus(405);
    }

    public static function filtrosInvalidos(): array
    {
        return [
            'lectura inválida' => ['/avisos', ['estado' => 'pendiente'], 'estado'],
            'lectura arreglo' => ['/avisos', ['estado' => ['leidos']], 'estado'],
            'búsqueda larga' => ['/avisos', ['buscar' => str_repeat('a', 151)], 'buscar'],
            'búsqueda arreglo' => ['/avisos', ['buscar' => ['a']], 'buscar'],
            'página cero' => ['/avisos', ['page' => 0], 'page'],
            'página negativa' => ['/avisos', ['page' => -1], 'page'],
            'página excesiva' => ['/reportes/proyectos', ['page' => 10001], 'page'],
            'página arreglo' => ['/reportes/proyectos', ['page' => [1]], 'page'],
            'estado incorrecto' => ['/reportes/proyectos', ['estado' => 'vigente'], 'estado'],
            'estado arreglo' => ['/reportes/asignaciones', ['estado' => ['vigente']], 'estado'],
            'empresa cero' => ['/reportes/proyectos', ['empresa_id' => 0], 'empresa_id'],
            'empresa texto' => ['/reportes/proyectos', ['empresa_id' => 'empresa'], 'empresa_id'],
            'empresa fuera bigint' => ['/reportes/proyectos', ['empresa_id' => '9223372036854775808'], 'empresa_id'],
            'profesor arreglo' => ['/reportes/direcciones', ['profesor_id' => [1]], 'profesor_id'],
            'filtro no aplica' => ['/reportes/carga_profesores', ['empresa_id' => -220101], 'empresa_id'],
            'estado no aplica' => ['/reportes/carga_profesores', ['estado' => 'vigente'], 'estado'],
            'proyecto no aplica' => ['/reportes/proyectos', ['proyecto_id' => -270201], 'proyecto_id'],
            'actor falsificado' => ['/reportes/candidaturas', ['actor_usuario_id' => -220001], 'actor_usuario_id'],
            'titular falsificado' => ['/avisos', ['destinatario_usuario_id' => -220004], 'destinatario_usuario_id'],
        ];
    }

    #[DataProvider('filtrosInvalidos')]
    public function test_filtros_invalidos_se_rechazan_sin_ignorarlos(string $ruta, array $filtros, string $campo): void
    {
        $this->entrar('admin');
        $this->get($ruta.'?'.http_build_query($filtros))->assertRedirect()->assertSessionHasErrors($campo);
    }

    public function test_filtros_booleanos_json_no_se_convierten_a_identificadores_o_paginas(): void
    {
        $this->entrar('admin');
        foreach (['empresa_id', 'page'] as $campo) {
            $this->json('GET', '/reportes/proyectos', [$campo => true])->assertUnprocessable()->assertJsonValidationErrors($campo);
        }
        $this->json('GET', '/avisos', ['page' => true])->assertUnprocessable()->assertJsonValidationErrors('page');
    }

    #[DataProvider('roles')]
    public function test_ux05_pendientes_del_panel_coinciden_con_la_lista_que_enlazan(string $rol): void
    {
        $this->entrar($rol);
        $pendientes = $this->get('/panel')->assertOk()->assertSee('Pendientes')->viewData('pendientes');
        $esperadas = ['admin' => ['revision', 'candidaturas', 'direcciones', 'avisos'], 'empresa' => ['evaluacion', 'preseleccion', 'correccion', 'avisos'],
            'alumno' => ['avisos'], 'profesor' => ['avisos']][$rol];
        $this->assertNotSame([], $pendientes, 'La fixture debe dejar al menos un pendiente para '.$rol);
        foreach ($pendientes as $pendiente) {
            $this->assertContains($pendiente['clave'], $esperadas);
            $this->assertGreaterThan(0, $pendiente['cantidad']);
            $this->assertSame(parse_url(url('/'), PHP_URL_HOST), parse_url($pendiente['url'], PHP_URL_HOST));
            $lista = $this->get($pendiente['url'])->assertOk();
            $total = match ($pendiente['clave']) {
                'avisos' => $lista->viewData('noLeidos'),
                'revision', 'correccion' => $lista->viewData('proyectos')->total(),
                default => $lista->viewData('solicitudes')->total(),
            };
            $this->assertSame($total, $pendiente['cantidad'], $pendiente['clave']);
        }
    }

    public function test_ux05_panel_sin_pendientes_lo_dice_y_no_cuenta_lo_ajeno(): void
    {
        $this->entrar('alumno');
        while (($pendientes = $this->bandeja(['estado' => 'no_leidos'])->avisos)->count() > 0) {
            foreach ($pendientes as $aviso) {
                $this->post('/avisos/'.$aviso->id.'/leer')->assertRedirect();
            }
        }
        $respuesta = $this->get('/panel')->assertOk()->assertSee('No tienes tareas pendientes por ahora.');
        $this->assertSame([], $respuesta->viewData('pendientes'));
        $respuesta->assertDontSee('esperan revisión')->assertDontSee('por evaluar');
    }

    public function test_ux05_exporta_csv_completo_con_filtros_bom_y_etiquetas(): void
    {
        $this->entrar('admin');
        $filtros = ['buscar' => 'Proyecto WEB07', 'estado' => 'publicado'];
        $this->get('/reportes/proyectos?'.http_build_query($filtros))->assertOk()
            ->assertSee('href="'.e(route('reportes.exportar', ['proyectos'] + $filtros)).'"', false);
        $respuesta = $this->get('/reportes/proyectos/exportar?'.http_build_query($filtros))->assertOk();
        $this->assertStringStartsWith('text/csv', $respuesta->headers->get('Content-Type'));
        $this->assertStringContainsString('attachment; filename=reporte-proyectos-', $respuesta->headers->get('Content-Disposition'));
        $this->assertStringContainsString('no-store', $respuesta->headers->get('Cache-Control'));
        $contenido = $respuesta->streamedContent();
        $this->assertStringStartsWith("\xEF\xBB\xBF", $contenido);
        $lineas = array_map(str_getcsv(...), array_values(array_filter(explode("\n", substr($contenido, 3)), fn ($l) => $l !== '')));
        $this->assertSame(['Proyecto', 'Empresa', 'Estado', 'Cupo de alumnos', 'Alumnos vigentes', 'Directores vigentes'], $lineas[0]);
        $this->assertCount(19 + 1, $lineas, 'Todas las filas filtradas, no solo la primera página');
        $this->assertSame(['Publicado'], array_values(array_unique(array_column(array_slice($lineas, 1), 2))));
        $todos = $this->get('/reportes/proyectos/exportar?buscar=Proyecto+WEB07')->assertOk()->streamedContent();
        $this->assertSame(26 + 1, substr_count(trim(substr($todos, 3)), "\n") + 1, 'Supera las 20 filas de una página');
        $asignaciones = $this->get('/reportes/asignaciones/exportar?buscar=Proyecto+WEB07')->assertOk()->streamedContent();
        $this->assertMatchesRegularExpression('/,(Alumno|Dirección),(Vigente|Finalizada|Revocada),"\d{4}-\d{2}-\d{2} \d{2}:\d{2}",/u', $asignaciones);
        $this->assertStringNotContainsString('@example.invalid', $asignaciones);
    }

    #[DataProvider('noAdministradores')]
    public function test_ux05_exportacion_restringida_al_administrador(string $rol): void
    {
        $this->entrar($rol);
        foreach (['proyectos', 'candidaturas', 'direcciones', 'carga_profesores', 'asignaciones'] as $tipo) {
            $this->get('/reportes/'.$tipo.'/exportar')->assertForbidden();
        }
    }

    public function test_ux05_exportacion_valida_filtros_y_neutraliza_formulas(): void
    {
        $this->entrar('admin');
        $this->get('/reportes/carga_profesores/exportar?estado=pendiente')->assertSessionHasErrors('estado');
        $this->get('/reportes/proyectos/exportar?empresa_id=abc')->assertSessionHasErrors('empresa_id');
        $this->get('/reportes/otro/exportar')->assertNotFound();
        $this->assertSame("'=HYPERLINK(\"x\")", ReporteController::celdaSegura('=HYPERLINK("x")'));
        $this->assertSame("'+1", ReporteController::celdaSegura('+1'));
        $this->assertSame("'@SUM(A1)", ReporteController::celdaSegura('@SUM(A1)'));
        $this->assertSame('Proyecto = 1', ReporteController::celdaSegura('Proyecto = 1'));
    }

    private function solicitud(string $tipo, int $id): object
    {
        return $this->get('/participacion/'.$tipo.'/'.$id)->assertOk()->viewData('detalle');
    }

    private function enviar(string $tipo, int $proyecto): int
    {
        $contexto = $this->get('/catalogo/'.$proyecto.'/participar')->assertOk()->viewData('contexto');
        $datos = ['version' => $contexto->version];
        if ($tipo === 'direccion') {
            $datos += ['experiencia_aplicable' => 'Experiencia académica WEB07', 'justificacion' => 'Acompañamiento académico WEB07'];
        }
        $respuesta = $this->post('/catalogo/'.$proyecto.'/participar', $datos)->assertRedirect()->assertSessionHasNoErrors();

        return (int) basename(parse_url($respuesta->headers->get('Location'), PHP_URL_PATH));
    }

    private function operar(string $tipo, int $id, string $accion, array $datos = []): void
    {
        $this->post('/participacion/'.$tipo.'/'.$id.'/'.$accion,
            ['version' => $this->solicitud($tipo, $id)->version] + $datos)
            ->assertRedirect('/participacion/'.$tipo.'/'.$id)->assertSessionHasNoErrors();
    }

    private function avisoVinculado(string $fragmento): object
    {
        $avisos = $this->bandeja()->avisos;
        foreach ($avisos as $aviso) {
            $respuesta = $this->get('/avisos/'.$aviso->id)->assertOk();
            $enlace = $respuesta->viewData('enlace');
            if ($enlace !== null && str_ends_with($enlace['url'], $fragmento)) {
                $this->get($enlace['url'])->assertOk();

                return $respuesta->viewData('aviso');
            }
        }
        $this->fail('No se encontró el aviso propio vinculado a '.$fragmento);
    }

    public function test_recorrido_integral_ca01_a_ca10_con_avisos_de_publicacion_postulacion_decision_y_ciclo(): void
    {
        // CA-09: creación, envío, validación del cupo y resolución consultable.
        $this->entrar('empresa');
        $creado = $this->post('/empresa/proyectos', [
            'titulo' => 'Entrega integral WEB07', 'descripcion' => 'Proyecto académico integral',
            'problematica' => 'Necesidad de organización', 'objetivos' => 'Organizar el proceso',
            'justificacion' => 'Mejora del seguimiento', 'alcance' => 'Una entrega académica', 'cupo_maximo_alumnos' => 2,
        ])->assertRedirect()->assertSessionHasNoErrors();
        $id = (int) basename(parse_url($creado->headers->get('Location'), PHP_URL_PATH));
        $p = $this->get('/empresa/proyectos/'.$id)->assertOk()->viewData('proyecto');
        $this->post('/empresa/proyectos/'.$id.'/enviar', ['version' => $p->version])->assertRedirect()->assertSessionHasNoErrors();
        $this->entrar('admin');
        $this->avisoVinculado('/admin/proyectos/'.$id);
        $p = $this->get('/admin/proyectos/'.$id)->assertOk()->viewData('proyecto');
        $revision = collect($p->revisiones)->sortByDesc('numero')->first();
        $this->post('/admin/proyectos/'.$id.'/resolver', ['version' => $p->version, 'revision_id' => $revision->id,
            'resultado' => 'aprobada', 'motivo' => 'Cupo y contenido aprobados WEB07', 'cupo_validado' => 2])
            ->assertRedirect()->assertSessionHasNoErrors();
        $this->entrar('empresa');
        $this->assertSame('publicado', $this->get('/empresa/proyectos/'.$id)->assertOk()->viewData('proyecto')->estado);
        $this->avisoVinculado('/empresa/proyectos/'.$id);

        // CA-01, CA-02 y CA-08: tres activas, estados propios y duplicado rechazado.
        $this->entrar('web06-alumno-8@example.invalid');
        $candidatura = $this->enviar('candidatura', $id);
        $this->enviar('candidatura', -260220);
        $this->enviar('candidatura', -260221);
        $listado = $this->get('/participacion/candidatura')->assertOk()->viewData('solicitudes');
        $this->assertSame(3, $listado->total());
        $this->assertSame('pendiente_evaluacion', $this->solicitud('candidatura', $candidatura)->solicitud->estado);
        foreach ([-260222, $id] as $bloqueado) {
            $version = $this->get('/catalogo/'.$bloqueado.'/participar')->assertOk()->viewData('contexto')->version;
            $this->post('/catalogo/'.$bloqueado.'/participar', ['version' => $version])->assertRedirect()->assertSessionHasErrors('operacion');
        }
        // CA-07: peticiones directas no sustituyen el permiso del rol.
        $this->post('/participacion/candidatura/'.$candidatura.'/aprobar', [
            'version' => $this->solicitud('candidatura', $candidatura)->version, 'motivo' => 'Intento sin permiso',
        ])->assertForbidden();
        $this->entrar('empresa');
        $this->avisoVinculado('/participacion/candidatura/'.$candidatura);
        $detalle = $this->solicitud('candidatura', $candidatura);
        $this->assertEqualsCanonicalizing(['dura', 'blanda'], array_unique(array_column($detalle->perfil->habilidades, 'tipo')));
        $this->operar('candidatura', $candidatura, 'evaluar', [
            'puntuaciones' => [
                'tecnico' => ['puntuacion' => 2, 'comentario' => 'Programación suficiente'],
                'blando' => ['puntuacion' => 2, 'comentario' => 'Colaboración suficiente'],
                'academico' => ['puntuacion' => 2, 'comentario' => 'Formación suficiente'],
            ], 'comentarios' => 'EVALUACION_PRIVADA_INTEGRAL_WEB07', 'recomendada' => true,
        ]);
        $this->operar('candidatura', $candidatura, 'preseleccionar');
        $this->assertNull($this->solicitud('candidatura', $candidatura)->asignacion);
        // CA-03/05/06: habilidades, ausencia de asignación previa e identificación administrativa.
        $this->entrar('admin');
        $this->operar('candidatura', $candidatura, 'aprobar', ['motivo' => 'AUTORIZACION_PRIVADA_INTEGRAL_WEB07']);
        $autorizada = $this->solicitud('candidatura', $candidatura);
        $this->assertSame('vigente', $autorizada->asignacion->estado);
        $this->assertStringContainsString('Admin WEB02', json_encode($autorizada->decisiones, JSON_UNESCAPED_UNICODE));

        // CA-04: el tercer proyecto ocupa carga y la cuarta autorización se rechaza.
        $this->entrar('web07-profesor-1@example.invalid');
        $direccion = $this->enviar('direccion', $id);
        $cuarta = $this->enviar('direccion', -260223);
        $this->entrar('admin');
        $this->operar('direccion', $direccion, 'aprobar', ['motivo' => 'Dirección autorizada WEB07']);
        $this->post('/participacion/direccion/'.$cuarta.'/aprobar', ['version' => $this->solicitud('direccion', $cuarta)->version,
            'motivo' => 'No debe exceder tres proyectos'])->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertNull($this->solicitud('direccion', $cuarta)->asignacion);
        $this->resumen($this->reporte('carga_profesores', ['profesor_id' => -270011])->resumen, ['proyectos_vigentes' => 3]);
        foreach (['iniciar', 'finalizar'] as $accion) {
            $seguimiento = $this->get('/seguimiento/proyectos/'.$id)->assertOk()->viewData('detalle');
            $datos = ['version' => $seguimiento->version];
            if ($accion === 'finalizar') {
                $datos['motivo'] = 'Cierre académico WEB07';
            }
            $this->post('/seguimiento/proyectos/'.$id.'/'.$accion, $datos)
                ->assertRedirect()->assertSessionHasNoErrors();
        }
        // CA-10: destinatarios reales consultan enlaces propios; marcar leído no cambia el proceso.
        foreach (['web06-alumno-8@example.invalid', 'web07-profesor-1@example.invalid', 'empresa'] as $cuenta) {
            $this->entrar($cuenta);
            $aviso = $this->avisoVinculado('/seguimiento/proyectos/'.$id);
            $this->assertNull($aviso->fecha_lectura);
            $this->post('/avisos/'.$aviso->id.'/leer')->assertRedirect('/avisos/'.$aviso->id)->assertSessionHasNoErrors();
            $this->assertNotNull($this->get('/avisos/'.$aviso->id)->assertOk()->viewData('aviso')->fecha_lectura);
            $this->get('/avisos')->assertOk()->assertDontSee('EVALUACION_PRIVADA_INTEGRAL_WEB07')->assertDontSee('AUTORIZACION_PRIVADA_INTEGRAL_WEB07');
            $this->assertSame('finalizado', $this->get('/seguimiento/proyectos/'.$id)->assertOk()->viewData('detalle')->proyecto->estado);
        }
    }
}
