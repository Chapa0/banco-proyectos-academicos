<?php

namespace Tests\Integration;

use Illuminate\Foundation\Http\Middleware\PreventRequestForgery;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\PostgresTestCase;
use Throwable;

class CsrfActivoEnPublicacion extends PreventRequestForgery
{
    protected function runningUnitTests()
    {
        return false;
    }
}

class PublicacionProyectosTest extends PostgresTestCase
{
    private const PASSWORD = 'PruebaSegura-2026!';

    protected function setUp(): void
    {
        parent::setUp();
        if (! getenv('BANCO_TEST_WEB04')) {
            $this->markTestSkipped('Ejecuta python tests/publicacion.py para la integración WEB-04.');
        }
    }

    public function call($method, $uri, $parameters = [], $cookies = [], $files = [], $server = [], $content = null)
    {
        $conexion = DB::connection('pgsql');
        $nivel = $conexion->transactionLevel();
        if ($nivel === 0) {
            return parent::call($method, $uri, $parameters, $cookies, $files, $server, $content);
        }
        // La base exterior aísla cada caso. Cada petición usa un savepoint para
        // que un SELECT rechazado no deje abortada la siguiente petición del
        // contenedor persistente, a diferencia de la conexión autocommit real.
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

    private function entrar(string $rol = 'empresa'): void
    {
        $this->post('/login', ['correo' => 'web02-'.$rol.'@example.invalid', 'password' => self::PASSWORD])
            ->assertRedirect('/panel');
    }

    private function cambiarActor(string $rol): void
    {
        $this->post('/logout')->assertRedirect();
        $this->entrar($rol);
    }

    private function datos(array $cambio = []): array
    {
        return array_replace([
            'titulo' => 'Control de inventario WEB04',
            'descripcion' => 'Sistema para registrar entradas y salidas.',
            'problematica' => 'La empresa pierde la trazabilidad de los artículos.',
            'objetivos' => 'Consultar existencias y movimientos.',
            'justificacion' => 'Reducir diferencias en las existencias.',
            'alcance' => 'Registro, consulta y reportes internos.',
            'cupo_maximo_alumnos' => 3,
            'requisitos_academicos' => 'Bases de datos y programación.',
            'duracion_estimada' => 'Doce semanas',
            'modalidad' => 'remota',
            'fecha_inicio_estimada' => '2027-03-01',
            'fecha_fin_estimada' => '2027-06-01',
            'recursos' => 'Equipo de desarrollo y datos de ejemplo.',
            'habilidades_seleccionadas' => [],
        ], $cambio);
    }

    private function detalle(int $id, bool $admin = false): object
    {
        $response = $this->get(($admin ? '/admin/proyectos/' : '/empresa/proyectos/').$id)->assertOk();
        $proyecto = $response->viewData('proyecto');
        $this->assertIsObject($proyecto);

        return $proyecto;
    }

    private function crear(array $datos = []): object
    {
        $response = $this->post('/empresa/proyectos', $datos ?: $this->datos())
            ->assertRedirect()->assertSessionHasNoErrors();
        $path = parse_url($response->headers->get('Location'), PHP_URL_PATH);
        $this->assertMatchesRegularExpression('~/empresa/proyectos/[0-9]+$~', $path);

        return $this->detalle((int) basename($path));
    }

    private function enviar(object $proyecto): object
    {
        $this->post('/empresa/proyectos/'.$proyecto->id.'/enviar', ['version' => $proyecto->version])
            ->assertRedirect()->assertSessionHasNoErrors();

        return $this->detalle((int) $proyecto->id);
    }

    private function revision(object $proyecto): object
    {
        $revision = collect($proyecto->revisiones)->sortByDesc('numero')->first();
        $this->assertNotNull($revision);

        return $revision;
    }

    private function resolucion(object $proyecto, string $resultado = 'aprobada', array $extra = []): array
    {
        return array_replace([
            'revision_id' => $this->revision($proyecto)->id,
            'version' => $proyecto->version,
            'resultado' => $resultado,
            'motivo' => 'Revisión administrativa de prueba.',
            'cupo_validado' => $resultado === 'aprobada' ? $proyecto->cupo_maximo_alumnos : null,
        ], $extra);
    }

    private function conservarCookie(): void
    {
        // El contenedor PHPUnit persiste; una cookie evita iniciar otra sesión
        // al seguir la redirección y reproduce el recorrido de un navegador.
        $this->withCookie(config('session.cookie'), session()->getId());
    }

    public function test_invitado_no_consulta_ni_modifica_empresa_proyectos_o_revision(): void
    {
        foreach (['/empresa', '/empresa/proyectos', '/empresa/proyectos/crear', '/admin/proyectos'] as $url) {
            $this->get($url)->assertRedirect('/login');
        }
        $this->post('/empresa/proyectos', $this->datos())->assertRedirect('/login');
        $this->put('/empresa', ['razon_social' => 'No autorizada'])->assertRedirect('/login');
        $this->post('/admin/proyectos/1/resolver', [])->assertRedirect('/login');
    }

    #[DataProvider('rolesSinEmpresa')]
    public function test_otros_roles_no_realizan_operaciones_de_empresa(string $rol): void
    {
        $this->entrar($rol);
        $this->get('/empresa')->assertForbidden();
        $this->get('/empresa/proyectos')->assertForbidden();
        $this->post('/empresa/proyectos', $this->datos(['autor_usuario_id' => -220005]))->assertForbidden();
    }

    public static function rolesSinEmpresa(): array
    {
        return [['admin'], ['alumno'], ['profesor']];
    }

    #[DataProvider('rolesSinRevision')]
    public function test_empresa_alumno_profesor_no_revisan_como_administrador(string $rol): void
    {
        $this->entrar($rol);
        $this->get('/admin/proyectos')->assertForbidden();
        $this->post('/admin/proyectos/1/resolver', ['administrador_id' => -220001])->assertForbidden();
    }

    public static function rolesSinRevision(): array
    {
        return [['empresa'], ['alumno'], ['profesor']];
    }

    public function test_empresa_actualiza_solo_sus_datos_y_rechaza_empresa_falsificada(): void
    {
        $this->entrar();
        $actual = $this->get('/empresa')->assertOk()->viewData('empresa');
        $this->put('/empresa', ['version' => $actual->version, 'empresa_id' => -220102,
            'razon_social' => 'No debe alterar otra empresa'])->assertSessionHasErrors('empresa_id');
        $this->put('/empresa', [
            'version' => $actual->version,
            'razon_social' => 'Empresa actualizada WEB04', 'sector' => 'Tecnología',
            'contacto_nombre' => 'Contacto de prueba', 'contacto_correo' => 'contacto@example.invalid',
            'contacto_telefono' => '5550102030', 'identificacion' => 'Ficticia WEB04',
        ])->assertRedirect()->assertSessionHasNoErrors();
        $actualizada = $this->get('/empresa')->assertOk()->viewData('empresa');
        $this->assertSame('Empresa actualizada WEB04', $actualizada->razon_social);
        $this->assertSame(-220101, (int) $actualizada->id);
        $this->cambiarActor('otra-empresa');
        $otra = $this->get('/empresa')->assertOk()->viewData('empresa');
        $this->assertSame('Otra empresa WEB02', $otra->razon_social);
    }

    public function test_formulario_vencido_de_empresa_no_sobrescribe_otro_cambio(): void
    {
        $this->entrar();
        $empresa = $this->get('/empresa')->assertOk()->viewData('empresa');
        $datos = ['version' => $empresa->version, 'razon_social' => 'Nombre vigente WEB04'];
        $this->put('/empresa', $datos)->assertSessionHasNoErrors();
        $this->put('/empresa', array_replace($datos, ['razon_social' => 'Nombre obsoleto WEB04']))->assertSessionHasErrors();
        $this->assertSame('Nombre vigente WEB04', $this->get('/empresa')->assertOk()->viewData('empresa')->razon_social);
    }

    public function test_borrador_admite_solo_titulo_y_no_inventa_cupo_ni_habilidades(): void
    {
        $this->entrar();
        $this->post('/empresa/proyectos', ['titulo' => 'Borrador manipulado', 'empresa_id' => -220102,
            'autor_usuario_id' => -220006])->assertSessionHasErrors(['empresa_id', 'autor_usuario_id']);
        $p = $this->crear(['titulo' => 'Borrador incompleto WEB04']);
        $this->assertSame('borrador', $p->estado);
        $this->assertSame(-220101, (int) $p->empresa_id);
        $this->assertSame(-220005, (int) $p->autor_usuario_id);
        $this->assertNull($p->cupo_maximo_alumnos);
        $this->assertCount(0, $p->habilidades);
        $this->assertCount(0, $p->revisiones);
        $this->get('/empresa/proyectos')->assertOk()->assertSee('Borrador incompleto WEB04');
    }

    #[DataProvider('camposObligatorios')]
    public function test_envio_exige_cada_uno_de_los_seis_campos_originales(string $campo): void
    {
        $this->entrar();
        if ($campo === 'titulo') {
            $this->post('/empresa/proyectos', $this->datos([$campo => " \t\n "]))->assertSessionHasErrors('titulo');

            return;
        }
        $p = $this->crear($this->datos([$campo => null]));
        $this->post('/empresa/proyectos/'.$p->id.'/enviar', ['version' => $p->version])->assertSessionHasErrors($campo);
        $actual = $this->detalle((int) $p->id);
        $this->assertSame('borrador', $actual->estado);
        $this->assertCount(0, $actual->revisiones);
    }

    public static function camposObligatorios(): array
    {
        return array_map(fn (string $campo) => [$campo], ['titulo', 'descripcion', 'problematica', 'objetivos', 'justificacion', 'alcance']);
    }

    public function test_envio_requiere_cupo_y_borrador_no_impone_habilidades_minimas(): void
    {
        $this->entrar();
        $p = $this->crear($this->datos(['cupo_maximo_alumnos' => null]));
        $this->post('/empresa/proyectos/'.$p->id.'/enviar', ['version' => $p->version])->assertSessionHasErrors('cupo_maximo_alumnos');
        $p = $this->detalle((int) $p->id);
        $this->put('/empresa/proyectos/'.$p->id, $this->datos(['version' => $p->version, 'cupo_maximo_alumnos' => 2]))
            ->assertSessionHasNoErrors();
        $enviado = $this->enviar($this->detalle((int) $p->id));
        $this->assertSame('en_revision', $enviado->estado);
        $this->assertCount(0, $enviado->habilidades);
        $this->assertCount(1, $enviado->revisiones);
    }

    public function test_edicion_preserva_datos_opcionales_y_habilidades_seleccionadas(): void
    {
        $this->entrar();
        $p = $this->crear();
        $this->put('/empresa/proyectos/'.$p->id, $this->datos([
            'version' => $p->version, 'habilidades_seleccionadas' => [1],
            'niveles' => [1 => 'Conocimientos básicos'], 'obligatorias' => [1],
        ]))->assertRedirect()->assertSessionHasNoErrors();
        $p = $this->detalle((int) $p->id);
        $this->assertSame('remota', $p->modalidad);
        $this->assertSame('2027-03-01', $p->fecha_inicio_estimada);
        $this->assertSame('Doce semanas', $p->duracion_estimada);
        $this->assertCount(1, $p->habilidades);
        $this->assertSame(1, (int) $p->habilidades[0]->habilidad_id);
        $this->assertTrue($p->habilidades[0]->obligatoria);
        $enviado = $this->enviar($p);
        $this->assertCount(1, $this->revision($enviado)->instantanea_contenido->habilidades);
    }

    public function test_otro_representante_no_consulta_edita_ni_envia_proyecto_ajeno(): void
    {
        $this->entrar();
        $p = $this->crear();
        $this->cambiarActor('otra-empresa');
        $this->get('/empresa/proyectos')->assertOk()->assertDontSee($p->titulo);
        $this->get('/empresa/proyectos/'.$p->id)->assertNotFound();
        $this->get('/empresa/proyectos/'.$p->id.'/editar')->assertNotFound();
        $this->put('/empresa/proyectos/'.$p->id, $this->datos(['version' => $p->version]))->assertNotFound();
        $this->post('/empresa/proyectos/'.$p->id.'/enviar', ['version' => $p->version])->assertNotFound();
    }

    public function test_administrador_puede_consultar_borrador_sin_resolverlo_ni_editarlo(): void
    {
        $this->entrar();
        $p = $this->crear(['titulo' => 'Borrador para consulta administrativa']);
        $this->cambiarActor('admin');
        $p = $this->detalle((int) $p->id, true);
        $this->assertSame('borrador', $p->estado);
        $this->get('/admin/proyectos?estado=borrador')->assertOk()->assertSee($p->titulo);
        $this->post('/admin/proyectos/'.$p->id.'/resolver', ['version' => $p->version, 'revision_id' => 1,
            'resultado' => 'aprobada', 'motivo' => 'No existe envío', 'cupo_validado' => 3])->assertNotFound();
        $this->assertSame('borrador', $this->detalle((int) $p->id, true)->estado);
    }

    public function test_edicion_y_doble_envio_no_alteran_una_revision_pendiente(): void
    {
        $this->entrar();
        $borrador = $this->crear();
        $p = $this->enviar($borrador);
        $this->get('/empresa/proyectos/'.$p->id.'/editar')->assertForbidden();
        $this->put('/empresa/proyectos/'.$p->id, $this->datos(['version' => $p->version, 'titulo' => 'Cambio indebido']))
            ->assertSessionHasErrors();
        $this->post('/empresa/proyectos/'.$p->id.'/enviar', ['version' => $borrador->version])->assertSessionHasErrors();
        $actual = $this->detalle((int) $p->id);
        $this->assertSame($borrador->titulo, $actual->titulo);
        $this->assertCount(1, $actual->revisiones);
        $this->assertSame('en_revision', $actual->estado);
    }

    public function test_formulario_obsoleto_no_sobrescribe_contenido_actualizado(): void
    {
        $this->entrar();
        $p = $this->crear();
        $this->put('/empresa/proyectos/'.$p->id, $this->datos(['version' => $p->version, 'titulo' => 'Título vigente']))
            ->assertSessionHasNoErrors();
        $this->put('/empresa/proyectos/'.$p->id, $this->datos(['version' => $p->version, 'titulo' => 'Título anterior']))
            ->assertSessionHasErrors();
        $actual = $this->detalle((int) $p->id);
        $this->assertSame('Título vigente', $actual->titulo);
        $this->assertNotSame($p->version, $actual->version);
        $this->post('/empresa/proyectos/'.$p->id.'/enviar', ['version' => $p->version])->assertSessionHasErrors();
        $this->assertCount(0, $this->detalle((int) $p->id)->revisiones);
    }

    public function test_publicacion_valida_cupo_exacto_y_conserva_autoria_revision_y_motivo(): void
    {
        $this->entrar();
        $p = $this->enviar($this->crear());
        $revision = $this->revision($p);
        $this->cambiarActor('admin');
        $pendiente = $this->detalle((int) $p->id, true);
        $this->get('/admin/proyectos')->assertOk()->assertSee($p->titulo);
        $this->post('/admin/proyectos/'.$p->id.'/resolver', $this->resolucion($pendiente, extra: ['cupo_validado' => 2]))
            ->assertSessionHasErrors();
        $sinResolver = $this->detalle((int) $p->id, true);
        $this->assertSame('en_revision', $sinResolver->estado);
        $this->assertNull($this->revision($sinResolver)->decision);
        $this->post('/admin/proyectos/'.$p->id.'/resolver', $this->resolucion($sinResolver, extra: ['administrador_usuario_id' => -220003]))
            ->assertSessionHasErrors('administrador_usuario_id');
        $this->post('/admin/proyectos/'.$p->id.'/resolver', $this->resolucion($sinResolver))
            ->assertRedirect()->assertSessionHasNoErrors();
        $publicado = $this->detalle((int) $p->id, true);
        $this->assertSame('publicado', $publicado->estado);
        $this->assertSame(3, (int) $publicado->cupo_maximo_alumnos);
        $this->assertSame((int) $revision->id, (int) $publicado->revision_publicada_id);
        $aprobada = $this->revision($publicado);
        $this->assertSame('aprobada', $aprobada->estado_revision);
        $this->assertSame('aprobada', $aprobada->decision->resultado);
        $this->assertSame('Revisión administrativa de prueba.', $aprobada->decision->justificacion);
        $this->assertSame('Admin WEB02', $aprobada->decision->administrador_nombre);
        $this->get('/admin/proyectos')->assertOk()->assertDontSee($p->titulo);
        $this->get('/admin/proyectos?estado=publicado')->assertOk()->assertSee($p->titulo);
    }

    public function test_resolucion_requiere_motivo_resultado_y_confirmacion_del_cupo(): void
    {
        $this->entrar();
        $p = $this->enviar($this->crear());
        $this->cambiarActor('admin');
        $p = $this->detalle((int) $p->id, true);
        foreach ([['motivo' => ''], ['resultado' => 'publicado'], ['cupo_validado' => null], ['cupo_validado' => 0]] as $cambio) {
            $this->post('/admin/proyectos/'.$p->id.'/resolver', $this->resolucion($p, extra: $cambio))->assertSessionHasErrors();
        }
        $actual = $this->detalle((int) $p->id, true);
        $this->assertSame('en_revision', $actual->estado);
        $this->assertNull($this->revision($actual)->decision);
    }

    public function test_devolucion_correccion_y_reenvio_conservan_dos_instantaneas(): void
    {
        $this->entrar();
        $p = $this->enviar($this->crear());
        $primera = $this->revision($p);
        $this->cambiarActor('admin');
        $admin = $this->detalle((int) $p->id, true);
        $this->post('/admin/proyectos/'.$p->id.'/resolver', $this->resolucion($admin, 'en_correccion', ['motivo' => 'Ajustar alcance y cupo']))
            ->assertSessionHasNoErrors();
        $this->cambiarActor('empresa');
        $devuelto = $this->detalle((int) $p->id);
        $this->assertSame('en_correccion', $devuelto->estado);
        $this->get('/empresa/proyectos/'.$p->id.'/editar')->assertOk();
        $this->put('/empresa/proyectos/'.$p->id, $this->datos(['version' => $devuelto->version,
            'alcance' => 'Alcance corregido de inventario', 'cupo_maximo_alumnos' => 2]))->assertSessionHasNoErrors();
        $nuevo = $this->enviar($this->detalle((int) $p->id));
        $this->assertCount(2, $nuevo->revisiones);
        $anterior = collect($nuevo->revisiones)->firstWhere('id', $primera->id);
        $this->assertSame('en_correccion', $anterior->estado_revision);
        $this->assertSame('Ajustar alcance y cupo', $anterior->decision->justificacion);
        $this->assertSame(3, (int) $anterior->instantanea_contenido->proyecto->cupo_maximo_alumnos);
        $segunda = $this->revision($nuevo);
        $this->assertSame(2, (int) $segunda->numero);
        $this->assertSame(2, (int) $segunda->instantanea_contenido->proyecto->cupo_maximo_alumnos);
        $this->assertSame('Alcance corregido de inventario', $segunda->instantanea_contenido->proyecto->alcance);
        $this->cambiarActor('admin');
        $admin = $this->detalle((int) $p->id, true);
        $this->post('/admin/proyectos/'.$p->id.'/resolver', $this->resolucion($admin, extra: ['revision_id' => $primera->id]))
            ->assertSessionHasErrors();
        $this->assertSame('en_revision', $this->detalle((int) $p->id, true)->estado);
    }

    #[DataProvider('resolucionesTerminales')]
    public function test_proyecto_publicado_o_rechazado_no_se_edita_reenvia_o_resuelve_otra_vez(string $resultado, string $estado): void
    {
        $this->entrar();
        $p = $this->enviar($this->crear());
        $this->cambiarActor('admin');
        $p = $this->detalle((int) $p->id, true);
        $datos = $this->resolucion($p, $resultado);
        $this->post('/admin/proyectos/'.$p->id.'/resolver', $datos)->assertSessionHasNoErrors();
        $this->post('/admin/proyectos/'.$p->id.'/resolver', $datos)->assertSessionHasErrors();
        $actual = $this->detalle((int) $p->id, true);
        $this->assertSame($estado, $actual->estado);
        $this->assertCount(1, $actual->revisiones);
        $this->cambiarActor('empresa');
        $this->get('/empresa/proyectos/'.$p->id.'/editar')->assertForbidden();
        $this->put('/empresa/proyectos/'.$p->id, $this->datos(['version' => $actual->version, 'titulo' => 'Cambio posterior']))
            ->assertSessionHasErrors();
        $this->post('/empresa/proyectos/'.$p->id.'/enviar', ['version' => $actual->version])->assertSessionHasErrors();
        $this->assertSame($p->titulo, $this->detalle((int) $p->id)->titulo);
    }

    public static function resolucionesTerminales(): array
    {
        return [['aprobada', 'publicado'], ['rechazada', 'rechazado']];
    }

    public function test_version_de_otro_proyecto_no_autoriza_revisar_la_instantanea(): void
    {
        $this->entrar();
        $uno = $this->enviar($this->crear());
        $dos = $this->enviar($this->crear($this->datos(['titulo' => 'Segundo proyecto WEB04'])));
        $this->cambiarActor('admin');
        $this->post('/admin/proyectos/'.$uno->id.'/resolver', $this->resolucion($dos))->assertSessionHasErrors();
        $actual = $this->detalle((int) $uno->id, true);
        $this->assertSame('en_revision', $actual->estado);
        $this->assertNull($this->revision($actual)->decision);
    }

    public function test_fechas_cupo_y_entradas_compuestas_invalidas_no_crean_borradores(): void
    {
        $this->entrar();
        foreach ([
            ['fecha_fin_estimada' => '2027-01-01'],
            ['cupo_maximo_alumnos' => 0], ['cupo_maximo_alumnos' => -1],
            ['cupo_maximo_alumnos' => 2147483648], ['cupo_maximo_alumnos' => ['entrada' => 2]],
            ['titulo' => ['entrada' => 'No es texto']], ['descripcion' => ['entrada' => 'No es texto']],
            ['habilidades' => [['habilidad_id' => 1]]],
        ] as $cambio) {
            $respuesta = $this->post('/empresa/proyectos', $this->datos($cambio));
            $this->assertTrue(session()->has('errors'), 'No se rechazó: '.implode(', ', array_keys($cambio)).'; HTTP '.$respuesta->getStatusCode());
            $respuesta->assertSessionHasErrors();
        }
        $this->post('/empresa/proyectos', $this->datos(['habilidades_seleccionadas' => [999999]]))->assertNotFound();
        $this->get('/empresa/proyectos')->assertOk()->assertDontSee('Control de inventario WEB04');
    }

    public function test_textos_con_html_se_escapan_en_lista_detalle_y_revision(): void
    {
        $this->entrar();
        $texto = '<script>alert("proyecto-web04")</script>';
        $p = $this->crear($this->datos(['titulo' => $texto, 'descripcion' => $texto]));
        $this->get('/empresa/proyectos')->assertOk()->assertSee($texto)->assertDontSee($texto, false);
        $this->get('/empresa/proyectos/'.$p->id)->assertOk()->assertSee($texto)->assertDontSee($texto, false);
        $this->enviar($p);
        $this->cambiarActor('admin');
        $this->get('/admin/proyectos/'.$p->id)->assertOk()->assertSee($texto)->assertDontSee($texto, false)
            ->assertDontSee('hash_contrasena')->assertDontSee(self::PASSWORD, false);
    }

    public function test_errores_con_arrays_permiten_volver_a_formulario_sin_error_interno(): void
    {
        $this->entrar();
        $this->from('/empresa/proyectos/crear')->post('/empresa/proyectos', $this->datos(['titulo' => ['entrada' => 'malformada']]))
            ->assertSessionHasErrors('titulo');
        $this->conservarCookie();
        $this->get('/empresa/proyectos/crear')->assertOk()->assertDontSee('malformada');
    }

    public function test_csrf_real_rechaza_alta_edicion_envio_y_resolucion_sin_token(): void
    {
        $this->entrar();
        $p = $this->crear();
        $this->app->bind(PreventRequestForgery::class, CsrfActivoEnPublicacion::class);
        $this->post('/empresa/proyectos', $this->datos())->assertStatus(419);
        $this->put('/empresa/proyectos/'.$p->id, $this->datos(['version' => $p->version]))->assertStatus(419);
        $this->post('/empresa/proyectos/'.$p->id.'/enviar', ['version' => $p->version])->assertStatus(419);
        $this->assertSame('borrador', $this->detalle((int) $p->id)->estado);
    }

    public function test_csrf_real_protege_resolucion_y_cambio_de_empresa(): void
    {
        $this->entrar();
        $p = $this->enviar($this->crear());
        $this->app->bind(PreventRequestForgery::class, CsrfActivoEnPublicacion::class);
        $empresa = $this->get('/empresa')->assertOk()->viewData('empresa');
        $this->put('/empresa', ['version' => $empresa->version, 'razon_social' => 'Cambio sin token'])->assertStatus(419);
        // Conservar el middleware y efectuar los cambios de sesión con CSRF válido.
        $this->post('/logout', ['_token' => session()->token()])->assertRedirect();
        $this->post('/login', ['_token' => session()->token(), 'correo' => 'web02-admin@example.invalid', 'password' => self::PASSWORD])
            ->assertRedirect('/panel');
        $p = $this->detalle((int) $p->id, true);
        $this->post('/admin/proyectos/'.$p->id.'/resolver', $this->resolucion($p))->assertStatus(419);
        $this->assertSame('en_revision', $this->detalle((int) $p->id, true)->estado);
    }

    #[DataProvider('resolucionesHistoricas')]
    public function test_revision_historica_sin_cupo_se_devuelve_o_rechaza_sin_reescribirla(string $resultado, string $estado): void
    {
        $this->entrar('admin');
        $p = $this->detalle(-240201, true);
        $antes = $this->revision($p)->instantanea_contenido;
        $this->assertNull($p->cupo_maximo_alumnos);
        $this->assertSame(1, (int) $antes->version_formato);
        $this->assertObjectNotHasProperty('cupo_maximo_alumnos', $antes->proyecto);
        $this->post('/admin/proyectos/'.$p->id.'/resolver', $this->resolucion($p, $resultado))
            ->assertRedirect()->assertSessionHasNoErrors();
        $actual = $this->detalle(-240201, true);
        $this->assertSame($estado, $actual->estado);
        $this->assertNull($actual->cupo_maximo_alumnos);
        $this->assertEquals($antes, $this->revision($actual)->instantanea_contenido);
    }

    public static function resolucionesHistoricas(): array
    {
        return [['en_correccion', 'en_correccion'], ['rechazada', 'rechazado']];
    }

    public function test_revision_historica_no_se_aprueba_inventando_un_cupo(): void
    {
        $this->entrar('admin');
        $p = $this->detalle(-240201, true);
        $this->post('/admin/proyectos/'.$p->id.'/resolver', $this->resolucion($p, extra: ['cupo_validado' => 3]))
            ->assertSessionHasErrors();
        $actual = $this->detalle(-240201, true);
        $this->assertSame('en_revision', $actual->estado);
        $this->assertNull($actual->cupo_maximo_alumnos);
        $this->assertNull($this->revision($actual)->decision);
    }

    public function test_recursos_inexistentes_y_versiones_invalidas_se_rechazan_sin_mutacion(): void
    {
        $this->entrar();
        $this->get('/empresa/proyectos/9223372036854775806')->assertNotFound();
        $p = $this->crear();
        foreach ([null, '', 'version-invalida', ['entrada' => $p->version]] as $version) {
            $this->post('/empresa/proyectos/'.$p->id.'/enviar', ['version' => $version])->assertSessionHasErrors('version');
        }
        $this->assertSame('borrador', $this->detalle((int) $p->id)->estado);
        $this->assertCount(0, $this->detalle((int) $p->id)->revisiones);
    }
}
