<?php

namespace Tests\Integration;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\PostgresTestCase;
use Throwable;

/** Pruebas de cambio de IDs sobre una DEMO-01 temporal, con la credencial real de aplicación. */
class AutorizacionRecursosTest extends PostgresTestCase
{
    private const CLAVE = 'Demo-Banco-2026';

    protected function setUp(): void
    {
        parent::setUp();
        if (! getenv('BANCO_TEST_AUTORIZACION')) {
            $this->markTestSkipped('Ejecuta py -3.12 tests/autorizacion.py para preparar la base temporal.');
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

    private function usuario(string $correo): int
    {
        return (int) DB::selectOne('SELECT id FROM banco.web_buscar_acceso_correo(?)', [$correo.'@demo.test'])->id;
    }

    private function entrar(string $correo): void
    {
        $this->post('/logout');
        $this->post('/login', ['correo' => $correo.'@demo.test', 'password' => self::CLAVE])->assertRedirect('/panel');
    }

    private function leer(string $funcion, array $parametros): mixed
    {
        $marcas = implode(',', array_fill(0, count($parametros), '?'));
        $json = DB::selectOne('SELECT banco.'.$funcion.'('.$marcas.') AS datos', $parametros)->datos;

        return json_decode($json, false, 512, JSON_THROW_ON_ERROR);
    }

    private function proyecto(string $estado): object
    {
        $lista = $this->leer('web_listar_proyectos', [$this->usuario('coordinacion'), '', $estado, 100, 0]);
        $this->assertNotEmpty($lista->datos);

        return $this->estadoProyecto((int) $lista->datos[0]->id);
    }

    private function estadoProyecto(int $id): object
    {
        return $this->leer('web_obtener_proyecto', [$this->usuario('coordinacion'), $id]);
    }

    private function solicitud(string $correo, string $tipo, string $estado): object
    {
        $lista = $this->leer('web_bandeja_participacion', [$this->usuario($correo), $tipo, $estado, '', 100, 0]);
        $this->assertNotEmpty($lista->datos);

        return $this->estadoSolicitud($tipo, (int) $lista->datos[0]->id);
    }

    private function estadoSolicitud(string $tipo, int $id): object
    {
        return $this->leer('web_detalle_participacion', [$this->usuario('coordinacion'), $tipo, $id]);
    }

    private function rutaDePrueba(\Illuminate\Routing\Route $ruta): string
    {
        $parametros = array_fill_keys($ruta->parameterNames(), '1');
        if (isset($parametros['tipo'])) {
            $parametros['tipo'] = str_starts_with($ruta->getName(), 'reportes.') ? 'proyectos' : 'candidatura';
        }
        if (isset($parametros['accion'])) {
            $parametros['accion'] = 'cancelar';
        }

        return route($ruta->getName(), $parametros, false);
    }

    public function test_todas_las_rutas_de_datos_exigen_sesion_en_cada_verbo(): void
    {
        $rutas = 0;
        foreach (Route::getRoutes() as $ruta) {
            if (in_array($ruta->uri(), ['/', 'login', 'up'], true)) {
                continue;
            }
            $this->assertNotNull($ruta->getName(), 'Ruta de datos sin clasificar: '.$ruta->uri());
            foreach ($ruta->methods() as $metodo) {
                $this->call($metodo, $this->rutaDePrueba($ruta))->assertRedirect('/login');
            }
            $rutas++;
        }
        $this->assertGreaterThan(50, $rutas);
    }

    public static function cuentasSinAdministracion(): array
    {
        return [['ana.torres'], ['alberto.cruz'], ['jorge.medina']];
    }

    #[DataProvider('cuentasSinAdministracion')]
    public function test_todas_las_rutas_administrativas_rechazan_otros_roles(string $correo): void
    {
        $antes = $this->leer('web_obtener_cuenta', [$this->usuario('coordinacion'), $this->usuario('coordinacion')]);
        $this->entrar($correo);
        foreach (Route::getRoutes() as $ruta) {
            if (str_starts_with($ruta->uri(), 'admin/') || str_starts_with($ruta->uri(), 'reportes/')) {
                foreach ($ruta->methods() as $metodo) {
                    $this->call($metodo, $this->rutaDePrueba($ruta), [
                        'actor' => $this->usuario('coordinacion'), 'version_acceso' => $antes->version_acceso,
                        'nombre' => 'Cambio no autorizado', 'correo' => 'intruso@demo.test', 'estado' => 'inactiva',
                        'motivo' => 'Intento de cambio de rol', 'password' => 'ClaveAjena-2026!', 'password_confirmation' => 'ClaveAjena-2026!',
                    ])->assertForbidden();
                }
            }
        }
        $this->assertEquals($antes, $this->leer('web_obtener_cuenta', [$this->usuario('coordinacion'), $this->usuario('coordinacion')]));
    }

    public function test_empresa_no_lee_edita_ni_envia_proyecto_ajeno_incluso_con_su_version_valida(): void
    {
        $antes = $this->proyecto('borrador');
        $id = (int) $antes->proyecto->id;
        $this->entrar('jorge.medina');
        $this->get('/empresa/proyectos/'.$id)->assertNotFound();
        $this->get('/empresa/proyectos/'.$id.'/editar')->assertNotFound();
        $datos = ['titulo' => 'Proyecto usurpado', 'version' => $antes->proyecto->version];
        $this->put('/empresa/proyectos/'.$id, $datos)->assertNotFound();
        $this->post('/empresa/proyectos/'.$id, $datos + ['_method' => 'PUT'])->assertNotFound();
        $this->post('/empresa/proyectos/'.$id.'/enviar', ['version' => $antes->proyecto->version])->assertNotFound();
        $this->assertEquals($antes, $this->estadoProyecto($id));
    }

    public function test_datos_de_empresa_y_creacion_no_admiten_suplantar_propietario(): void
    {
        $propio = $this->leer('web_obtener_empresa', [$this->usuario('jorge.medina')]);
        $ajeno = $this->leer('web_obtener_empresa', [$this->usuario('lucia.hernandez')]);
        $this->entrar('jorge.medina');
        $this->putJson('/empresa', ['razon_social' => 'Usurpada', 'version' => $propio->version, 'empresa_id' => $ajeno->id])
            ->assertUnprocessable()->assertJsonValidationErrors('empresa_id');
        $this->postJson('/empresa/proyectos', ['titulo' => 'Usurpado', 'empresa_id' => $ajeno->id])
            ->assertUnprocessable()->assertJsonValidationErrors('empresa_id');
        $this->assertEquals($propio, $this->leer('web_obtener_empresa', [$this->usuario('jorge.medina')]));
        $this->assertEquals($ajeno, $this->leer('web_obtener_empresa', [$this->usuario('lucia.hernandez')]));
    }

    public static function solicitudesAjenas(): array
    {
        return [
            ['mateo.juarez', 'camila.reyes', 'candidatura', 'pendiente_evaluacion'],
            ['sofia.mendoza', 'alberto.cruz', 'direccion', 'pendiente'],
        ];
    }

    #[DataProvider('solicitudesAjenas')]
    public function test_cancelar_y_consultar_no_admiten_intercambiar_solicitudes_del_mismo_rol(string $atacante, string $titular, string $tipo, string $estado): void
    {
        $antes = $this->solicitud($titular, $tipo, $estado);
        $id = (int) $antes->solicitud->id;
        $this->entrar($atacante);
        $this->get('/participacion/'.$tipo.'/'.$id)->assertForbidden();
        $this->post('/participacion/'.$tipo.'/'.$id.'/cancelar', ['version' => $antes->version])->assertForbidden();
        $this->assertEquals($antes, $this->estadoSolicitud($tipo, $id));
    }

    public function test_empresa_no_evalua_ni_preselecciona_candidatura_de_otra_empresa(): void
    {
        $antes = $this->solicitud('camila.reyes', 'candidatura', 'pendiente_evaluacion');
        $id = (int) $antes->solicitud->id;
        $this->entrar('jorge.medina');
        $criterios = array_fill_keys(['tecnico', 'blando', 'academico'], ['puntuacion' => 2, 'comentario' => 'Criterio completo']);
        $this->get('/participacion/candidatura/'.$id)->assertForbidden();
        $this->post('/participacion/candidatura/'.$id.'/evaluar', [
            'version' => $antes->version, 'puntuaciones' => $criterios, 'comentarios' => 'Evaluación ajena', 'recomendada' => true,
        ])->assertForbidden();
        $this->post('/participacion/candidatura/'.$id.'/preseleccionar', ['version' => $antes->version])->assertForbidden();
        $this->assertEquals($antes, $this->estadoSolicitud('candidatura', $id));
    }

    #[DataProvider('cuentasSinAdministracion')]
    public function test_otros_roles_no_autorizan_asignan_retiros_ni_cambian_el_ciclo(string $correo): void
    {
        $proyecto = $this->proyecto('en_curso');
        $id = (int) $proyecto->proyecto->id;
        $solicitud = $this->solicitud('valeria.gomez', 'candidatura', 'preseleccionada');
        $this->entrar($correo);
        foreach (['aprobar', 'rechazar'] as $accion) {
            $this->post('/participacion/candidatura/'.$solicitud->solicitud->id.'/'.$accion,
                ['version' => $solicitud->version, 'motivo' => 'Resolución ajena'])->assertForbidden();
        }
        foreach (['iniciar', 'reanudar', 'finalizar', 'cancelar', 'retirar_alumno', 'retirar_director'] as $accion) {
            $this->post('/seguimiento/proyectos/'.$id.'/'.$accion, [
                'version' => str_repeat('a', 64), 'motivo' => 'Operación no autorizada', 'asignacion_id' => 1,
            ])->assertForbidden();
        }
        $this->assertEquals($proyecto, $this->estadoProyecto($id));
        $this->assertEquals($solicitud, $this->estadoSolicitud('candidatura', (int) $solicitud->solicitud->id));
    }

    public function test_administrador_no_mezcla_revision_de_un_proyecto_con_otro(): void
    {
        $antes = $this->proyecto('en_revision');
        $otra = $this->proyecto('en_curso');
        $id = (int) $antes->proyecto->id;
        $this->entrar('coordinacion');
        $this->post('/admin/proyectos/'.$id.'/resolver', [
            'revision_id' => $otra->revisiones[0]->id, 'version' => $antes->proyecto->version,
            'resultado' => 'en_correccion', 'motivo' => 'Revisión de otro proyecto',
        ])->assertNotFound();
        $this->assertEquals($antes, $this->estadoProyecto($id));
        $this->assertEquals($otra, $this->estadoProyecto((int) $otra->proyecto->id));
    }

    public function test_retiro_exige_que_la_asignacion_pertenezca_al_proyecto_de_la_url(): void
    {
        $curso = $this->proyecto('en_curso');
        $otro = $this->proyecto('publicado');
        $admin = $this->usuario('coordinacion');
        $seguimiento = $this->leer('web_detalle_proyecto_participacion', [$admin, $curso->proyecto->id]);
        // Elegir el publicado que ya tiene alumnos y dirección aprobados.
        $lista = $this->leer('web_listar_proyectos', [$admin, '', 'publicado', 100, 0]);
        foreach ($lista->datos as $item) {
            $candidato = $this->leer('web_detalle_proyecto_participacion', [$admin, $item->id]);
            if ($candidato->alumnos !== [] && $candidato->directores !== []) {
                $otro = $this->estadoProyecto((int) $item->id);
                $asignaciones = $candidato;
                break;
            }
        }
        $this->assertNotEmpty($asignaciones->alumnos ?? []);
        $this->entrar('coordinacion');
        foreach (['retirar_alumno' => $asignaciones->alumnos[0]->id, 'retirar_director' => $asignaciones->directores[0]->id] as $accion => $ajena) {
            $this->post('/seguimiento/proyectos/'.$curso->proyecto->id.'/'.$accion, [
                'version' => $seguimiento->version, 'asignacion_id' => $ajena, 'motivo' => 'Asignación de otro proyecto',
            ])->assertNotFound();
        }
        $this->assertEquals($curso, $this->estadoProyecto((int) $curso->proyecto->id));
        $this->assertEquals($otro, $this->estadoProyecto((int) $otro->proyecto->id));
        $this->assertEquals($asignaciones, $this->leer('web_detalle_proyecto_participacion', [$admin, $otro->proyecto->id]));
    }

    public function test_avisos_son_personales_incluso_para_la_administracion(): void
    {
        $titular = $this->usuario('ana.torres');
        $bandeja = $this->leer('web_bandeja_avisos', [$titular, 'todos', '', 100, 0]);
        $id = (int) $bandeja->datos[0]->id;
        $antes = $this->leer('web_detalle_aviso', [$titular, $id]);
        foreach (['mateo.juarez', 'alberto.cruz', 'jorge.medina', 'coordinacion'] as $correo) {
            $this->entrar($correo);
            $this->get('/avisos/'.$id)->assertForbidden();
            $this->post('/avisos/'.$id.'/leer')->assertForbidden();
        }
        $this->assertEquals($antes, $this->leer('web_detalle_aviso', [$titular, $id]));
    }

    public function test_editar_perfil_no_admite_reemplazar_actor_por_campos_ocultos(): void
    {
        $actor = $this->usuario('ana.torres');
        $victima = $this->usuario('mateo.juarez');
        $antes = $this->leer('web_obtener_perfil_propio', [$actor]);
        $ajeno = $this->leer('web_obtener_perfil_propio', [$victima]);
        $this->entrar('ana.torres');
        foreach (['actor', 'usuario_id', 'alumno_id', 'id', 'titular_id'] as $campo) {
            $this->putJson('/perfil', ['version' => $antes->version, 'matricula' => $antes->perfil->matricula, $campo => $victima])
                ->assertUnprocessable()->assertJsonValidationErrors($campo);
        }
        $this->assertEquals($antes, $this->leer('web_obtener_perfil_propio', [$actor]));
        $this->assertEquals($ajeno, $this->leer('web_obtener_perfil_propio', [$victima]));
    }

    public function test_documentos_ajenos_no_se_descargan_ni_retiran_cambiando_el_id(): void
    {
        Storage::fake('local');
        $actor = $this->usuario('ana.torres');
        $this->entrar('ana.torres');
        $pdf = UploadedFile::fake()->createWithContent('CV propio.pdf', "%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\n%%EOF");
        $this->post('/perfil/documentos', [
            'tipo' => 'curriculum', 'archivo' => $pdf, 'titular_usuario_id' => $this->usuario('mateo.juarez'),
        ])->assertSessionHasNoErrors();
        $antes = $this->leer('web_documentos_perfil', [$actor, $actor]);
        $this->assertCount(1, $antes);
        $this->assertSame([], $this->leer('web_documentos_perfil', [$this->usuario('coordinacion'), $this->usuario('mateo.juarez')]));
        $id = (int) $antes[0]->id;
        $this->get('/documentos/'.$id)->assertOk();
        $archivos = Storage::disk('local')->allFiles();
        $contenido = Storage::disk('local')->get($archivos[0]);
        $this->entrar('mateo.juarez');
        $this->get('/documentos/'.$id)->assertNotFound();
        $this->delete('/perfil/documentos/'.$id)->assertNotFound();
        $this->post('/perfil/documentos/'.$id, ['_method' => 'DELETE'])->assertNotFound();
        $this->assertEquals($antes, $this->leer('web_documentos_perfil', [$actor, $actor]));
        $this->assertSame($contenido, Storage::disk('local')->get($archivos[0]));
    }

    public function test_foto_y_logo_se_quitan_por_sesion_sin_aceptar_un_titular_ajeno(): void
    {
        Storage::fake('local');
        $this->entrar('ana.torres');
        $this->post('/perfil/foto', ['imagen' => UploadedFile::fake()->image('foto.jpg', 80, 80)])->assertSessionHasNoErrors();
        $foto = $this->get('/perfil')->assertOk()->viewData('foto');
        $this->get('/imagenes/'.$foto)->assertOk()->assertHeader('Cache-Control', 'no-store, private');
        $this->entrar('mateo.juarez');
        $this->get('/imagenes/'.$foto)->assertNotFound();
        $this->delete('/perfil/foto', ['usuario_id' => $this->usuario('ana.torres'), 'imagen_id' => $foto])->assertNotFound();
        $this->entrar('ana.torres');
        $this->get('/imagenes/'.$foto)->assertOk();

        $this->entrar('lucia.hernandez');
        $this->post('/empresa/logo', ['imagen' => UploadedFile::fake()->image('logo.png', 80, 80)])->assertSessionHasNoErrors();
        $logo = $this->get('/empresa')->assertOk()->viewData('logo');
        $empresa = $this->leer('web_obtener_empresa', [$this->usuario('lucia.hernandez')]);
        $this->entrar('jorge.medina');
        $this->delete('/empresa/logo', ['empresa_id' => $empresa->id, 'imagen_id' => $logo])->assertNotFound();
        $this->get('/imagenes/'.$logo)->assertOk(); // Logos compartidos según UX-08.
        $this->entrar('lucia.hernandez');
        $this->assertEquals($logo, $this->get('/empresa')->assertOk()->viewData('logo'));
    }

    public function test_constancia_exige_titular_y_seguimiento_rechaza_proyecto_sin_relacion(): void
    {
        $solicitud = $this->solicitud('diego.morales', 'candidatura', 'aprobada');
        $this->entrar('diego.morales');
        $this->get('/participacion/candidatura/'.$solicitud->solicitud->id.'/constancia')->assertOk();
        $this->entrar('mateo.juarez');
        $this->get('/participacion/candidatura/'.$solicitud->solicitud->id.'/constancia')->assertNotFound();
        $this->get('/seguimiento/proyectos/'.$solicitud->proyecto->id)->assertForbidden();
        $borrador = $this->proyecto('borrador');
        $this->get('/catalogo/'.$borrador->proyecto->id)->assertNotFound();
    }

    public function test_no_se_agregan_borrados_de_negocio_por_cambiar_el_verbo(): void
    {
        $antes = $this->proyecto('borrador');
        $this->entrar('jorge.medina');
        foreach (['/empresa/proyectos/'.$antes->proyecto->id, '/admin/cuentas/1', '/participacion/candidatura/1'] as $ruta) {
            $this->delete($ruta)->assertStatus(405);
        }
        $this->assertEquals($antes, $this->estadoProyecto((int) $antes->proyecto->id));
    }

    public function test_cambio_de_clave_usa_la_sesion_aunque_se_envie_otro_usuario(): void
    {
        $actor = $this->usuario('ana.torres');
        $victima = $this->usuario('mateo.juarez');
        $antes = DB::selectOne('SELECT version_acceso,hash_contrasena FROM banco.web_buscar_acceso_id(?)', [$victima]);
        $this->entrar('ana.torres');
        $this->put('/clave', [
            'current_password' => self::CLAVE, 'password' => 'CambioPropio-2026!', 'password_confirmation' => 'CambioPropio-2026!',
            'usuario_id' => $victima, 'actor_usuario_id' => $victima,
        ])->assertRedirect('/panel')->assertSessionHasNoErrors();
        $despues = DB::selectOne('SELECT version_acceso,hash_contrasena FROM banco.web_buscar_acceso_id(?)', [$victima]);
        $this->assertTrue($antes->hash_contrasena === $despues->hash_contrasena);
        $this->assertSame($antes->version_acceso, $despues->version_acceso);
        $propio = DB::selectOne('SELECT hash_contrasena FROM banco.web_buscar_acceso_id(?)', [$actor]);
        $this->assertTrue(Hash::check('CambioPropio-2026!', $propio->hash_contrasena));
    }
}
