<?php

namespace Tests\Integration;

use Illuminate\Foundation\Http\Middleware\PreventRequestForgery;
use Illuminate\Http\UploadedFile;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\PostgresTestCase;
use Throwable;

class CsrfActivoEnParticipacion extends PreventRequestForgery
{
    protected function runningUnitTests()
    {
        return false;
    }
}

class ParticipacionTest extends PostgresTestCase
{
    private const PASSWORD = 'PruebaSegura-2026!';

    private ?string $cuenta = null;

    protected function setUp(): void
    {
        parent::setUp();
        if (! getenv('BANCO_TEST_WEB06')) {
            $this->markTestSkipped('Ejecuta python tests/participacion.py para la integración WEB-06.');
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

    private function contexto(int $proyecto): object
    {
        $datos = $this->get('/catalogo/'.$proyecto.'/participar')->assertOk()->viewData('contexto');
        $this->assertMatchesRegularExpression('/\A[a-f0-9]{64}\z/', $datos->version);

        return $datos;
    }

    private function solicitud(string $tipo, int $id): object
    {
        $datos = $this->get('/participacion/'.$tipo.'/'.$id)->assertOk()->viewData('detalle');
        $this->assertMatchesRegularExpression('/\A[a-f0-9]{64}\z/', $datos->version);

        return $datos;
    }

    private function proyectos(int $proyecto): object
    {
        $datos = $this->get('/seguimiento/proyectos/'.$proyecto)->assertOk()->viewData('detalle');
        $this->assertMatchesRegularExpression('/\A[a-f0-9]{64}\z/', $datos->version);

        return $datos;
    }

    private function listado(string $tipo, string $filtros = ''): LengthAwarePaginator
    {
        $datos = $this->get('/participacion/'.$tipo.$filtros)->assertOk()->viewData('solicitudes');
        $this->assertInstanceOf(LengthAwarePaginator::class, $datos);

        return $datos;
    }

    private function enviar(string $tipo = 'candidatura', int $proyecto = -260201, array $cambio = []): int
    {
        $datos = ['version' => $this->contexto($proyecto)->version];
        if ($tipo === 'direccion') {
            $datos += ['experiencia_aplicable' => 'Experiencia aplicable WEB06', 'justificacion' => 'Acompañar el aprendizaje del proyecto WEB06'];
        }
        $respuesta = $this->post('/catalogo/'.$proyecto.'/participar', array_replace($datos, $cambio))
            ->assertRedirect()->assertSessionHasNoErrors();
        $ruta = parse_url($respuesta->headers->get('Location'), PHP_URL_PATH);
        $this->assertMatchesRegularExpression('~\A/participacion/'.$tipo.'/-?\d+\z~', $ruta);

        return (int) basename($ruta);
    }

    private function operar(string $tipo, int $id, string $accion, array $datos = []): void
    {
        $this->post('/participacion/'.$tipo.'/'.$id.'/'.$accion,
            array_merge(['version' => $this->solicitud($tipo, $id)->version], $datos))
            ->assertRedirect('/participacion/'.$tipo.'/'.$id)->assertSessionHasNoErrors();
    }

    private function rubrica(array $cambio = []): array
    {
        return array_replace([
            'puntuaciones' => [
                'tecnico' => ['puntuacion' => 2, 'comentario' => 'Conocimientos técnicos suficientes'],
                'blando' => ['puntuacion' => 1, 'comentario' => 'Puede fortalecer la comunicación'],
                'academico' => ['puntuacion' => 2, 'comentario' => 'Formación académica pertinente'],
            ],
            'comentarios' => 'Evaluación general privada de la empresa WEB06', 'recomendada' => true,
        ], $cambio);
    }

    private function evaluar(int $id, array $cambio = []): void
    {
        $this->entrar('empresa');
        $this->operar('candidatura', $id, 'evaluar', $this->rubrica($cambio));
    }

    private function preseleccionar(int $id): void
    {
        $this->operar('candidatura', $id, 'preseleccionar');
    }

    private function aprobar(string $tipo, int $id): void
    {
        $this->entrar('admin');
        $this->operar($tipo, $id, 'aprobar', ['motivo' => 'Autorización administrativa WEB06']);
    }

    private function asignarAlumno(int $proyecto = -260201, string $alumno = 'alumno'): int
    {
        $this->entrar($alumno);
        $id = $this->enviar('candidatura', $proyecto);
        $this->evaluar($id);
        $this->preseleccionar($id);
        $this->aprobar('candidatura', $id);

        return $id;
    }

    private function asignarProfesor(int $proyecto = -260201, string $profesor = 'profesor'): int
    {
        $this->entrar($profesor);
        $id = $this->enviar('direccion', $proyecto);
        $this->aprobar('direccion', $id);

        return $id;
    }

    private function ciclo(int $proyecto, string $accion, array $datos = []): void
    {
        $this->post('/seguimiento/proyectos/'.$proyecto.'/'.$accion,
            array_merge(['version' => $this->proyectos($proyecto)->version], $datos))
            ->assertRedirect('/seguimiento/proyectos/'.$proyecto)->assertSessionHasNoErrors();
    }

    public function test_alumno_envia_consulta_y_cancela_con_historial_y_nuevo_registro(): void
    {
        $this->entrar();
        $id = $this->enviar();
        $actual = $this->solicitud('candidatura', $id);
        $this->assertSame('pendiente_evaluacion', $actual->solicitud->estado);
        $this->assertSame(-260201, $actual->proyecto->id);
        $this->assertContains('cancelar', $actual->acciones);
        $this->assertSame(1, $this->listado('candidatura')->total());
        $this->operar('candidatura', $id, 'cancelar');
        $cancelada = $this->solicitud('candidatura', $id);
        $this->assertSame('cancelada', $cancelada->solicitud->estado);
        $this->assertNotEmpty($cancelada->historial);
        $otra = $this->enviar();
        $this->assertNotSame($id, $otra);
        $this->assertSame(2, $this->listado('candidatura')->total());
    }

    public function test_cuarta_candidatura_activa_se_rechaza_y_cancelar_libera_un_espacio(): void
    {
        $this->entrar();
        $ids = [];
        foreach ([-260201, -260202, -260203] as $proyecto) {
            $ids[] = $this->enviar('candidatura', $proyecto);
        }
        $this->post('/catalogo/-260204/participar', ['version' => $this->contexto(-260204)->version])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame(3, $this->listado('candidatura')->total());
        $this->operar('candidatura', $ids[0], 'cancelar');
        $nuevo = $this->enviar('candidatura', -260204);
        $this->assertSame('pendiente_evaluacion', $this->solicitud('candidatura', $nuevo)->solicitud->estado);
        $this->assertSame(4, $this->listado('candidatura')->total());
    }

    public function test_doble_envio_del_mismo_formulario_no_duplica_la_candidatura(): void
    {
        $this->entrar();
        $datos = ['version' => $this->contexto(-260201)->version];
        $this->post('/catalogo/-260201/participar', $datos)->assertRedirect()->assertSessionHasNoErrors();
        $this->post('/catalogo/-260201/participar', $datos)->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame(1, $this->listado('candidatura')->total());
    }

    public function test_profesor_envia_experiencia_justificacion_y_cancela_solo_pendiente(): void
    {
        $this->entrar('profesor');
        $id = $this->enviar('direccion');
        $datos = $this->solicitud('direccion', $id);
        $this->assertSame('pendiente', $datos->solicitud->estado);
        $this->assertSame('Experiencia aplicable WEB06', $datos->solicitud->experiencia_aplicable);
        $this->assertSame('Acompañar el aprendizaje del proyecto WEB06', $datos->solicitud->justificacion);
        $this->operar('direccion', $id, 'cancelar');
        $this->assertSame('cancelada', $this->solicitud('direccion', $id)->solicitud->estado);
        $this->assertNotSame($id, $this->enviar('direccion'));
    }

    public function test_solicitudes_docentes_pendientes_no_tienen_maximo_de_tres(): void
    {
        $this->entrar('profesor');
        foreach ([-260201, -260202, -260203, -260204] as $proyecto) {
            $this->enviar('direccion', $proyecto);
        }
        $this->assertSame(4, $this->listado('direccion')->total());
    }

    public static function enviosInvalidos(): array
    {
        return [
            'version vacía' => ['alumno', [], 'version'],
            'versión inventada' => ['alumno', ['version' => 'version-inventada'], 'version'],
            'actor forjado' => ['alumno', ['actor' => -220001], 'actor'],
            'titular forjado' => ['alumno', ['alumno_id' => -260001], 'alumno_id'],
            'proyecto forjado' => ['alumno', ['proyecto_id' => -260225], 'proyecto_id'],
            'estado forjado' => ['alumno', ['estado' => 'aprobada'], 'estado'],
            'experiencia docente ausente' => ['profesor', ['justificacion' => 'Justificación'], 'experiencia_aplicable'],
            'justificación docente vacía' => ['profesor', ['experiencia_aplicable' => 'Experiencia', 'justificacion' => '  '], 'justificacion'],
            'experiencia como arreglo' => ['profesor', ['experiencia_aplicable' => ['inyección'], 'justificacion' => 'Justificación'], 'experiencia_aplicable'],
            'experiencia demasiado larga' => ['profesor', ['experiencia_aplicable' => str_repeat('x', 10001), 'justificacion' => 'Justificación'], 'experiencia_aplicable'],
        ];
    }

    #[DataProvider('enviosInvalidos')]
    public function test_envios_invalidos_no_crean_solicitudes(string $rol, array $cambio, string $campo): void
    {
        $this->entrar($rol);
        $datos = ['version' => $this->contexto(-260201)->version];
        if ($campo === 'version' && $cambio === []) {
            $datos = [];
        }
        $this->post('/catalogo/-260201/participar', array_replace($datos, $cambio))
            ->assertRedirect()->assertSessionHasErrors($campo);
        $this->assertSame(0, $this->listado($rol === 'alumno' ? 'candidatura' : 'direccion')->total());
    }

    public function test_una_evidencia_archivo_no_se_acepta_en_envios(): void
    {
        $this->entrar('profesor');
        $this->post('/catalogo/-260201/participar', [
            'version' => $this->contexto(-260201)->version, 'experiencia_aplicable' => 'Experiencia',
            'justificacion' => 'Justificación', 'archivo' => UploadedFile::fake()->create('evidencia.pdf', 2, 'application/pdf'),
        ])->assertRedirect()->assertSessionHasErrors('archivos');
        $this->assertSame(0, $this->listado('direccion')->total());
    }

    public function test_experiencia_y_justificacion_html_se_muestran_escapadas(): void
    {
        $this->entrar('profesor');
        $ataque = '<script>alert("WEB06-XSS")</script>';
        $id = $this->enviar('direccion', -260201, ['experiencia_aplicable' => $ataque, 'justificacion' => 'javascript:alert("WEB06-URL")']);
        $respuesta = $this->get('/participacion/direccion/'.$id)->assertOk();
        $respuesta->assertSee($ataque)->assertDontSee($ataque, false)->assertDontSee('href="javascript:', false);
        $this->entrar('admin');
        $this->get('/participacion/direccion/'.$id)->assertOk()->assertSee($ataque)->assertDontSee($ataque, false);
    }

    public function test_empresa_evalua_tres_criterios_preselecciona_y_admin_asigna(): void
    {
        $this->entrar();
        $id = $this->enviar();
        $this->evaluar($id);
        $evaluada = $this->solicitud('candidatura', $id);
        $this->assertSame('evaluada', $evaluada->solicitud->estado);
        $this->assertCount(1, $evaluada->evaluaciones);
        $this->preseleccionar($id);
        $this->assertSame('preseleccionada', $this->solicitud('candidatura', $id)->solicitud->estado);
        $this->aprobar('candidatura', $id);
        $aprobada = $this->solicitud('candidatura', $id);
        $this->assertSame('aprobada', $aprobada->solicitud->estado);
        $this->assertNotEmpty($aprobada->decisiones);
        $this->entrar();
        $propia = $this->solicitud('candidatura', $id);
        $this->assertCount(1, $propia->evaluaciones);
        $this->assertNotContains('cancelar', $propia->acciones);
        $this->get('/seguimiento/proyectos/-260201')->assertOk();
    }

    public function test_aprobacion_sin_evaluacion_y_preseleccion_se_rechaza_sin_asignar(): void
    {
        $this->entrar();
        $id = $this->enviar();
        $this->entrar('admin');
        $this->post('/participacion/candidatura/'.$id.'/aprobar', [
            'version' => $this->solicitud('candidatura', $id)->version, 'motivo' => 'No debe autorizar',
        ])->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame('pendiente_evaluacion', $this->solicitud('candidatura', $id)->solicitud->estado);
    }

    public function test_reevaluar_conserva_versiones_e_invalida_preseleccion(): void
    {
        $this->entrar();
        $id = $this->enviar();
        $this->evaluar($id);
        $this->preseleccionar($id);
        $this->evaluar($id, ['comentarios' => 'Segunda evaluación distinta WEB06', 'recomendada' => false]);
        $datos = $this->solicitud('candidatura', $id);
        $this->assertSame('evaluada', $datos->solicitud->estado);
        $this->assertCount(2, $datos->evaluaciones);
        $pagina = $this->get('/participacion/candidatura/'.$id)->assertOk()->getContent();
        $texto = preg_replace('/\s+/u', ' ', html_entity_decode(strip_tags($pagina), ENT_QUOTES | ENT_HTML5, 'UTF-8'));
        $this->assertStringContainsString('Recomendación: No', $texto);
        $this->post('/participacion/candidatura/'.$id.'/preseleccionar', ['version' => $datos->version])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->entrar('admin');
        $this->post('/participacion/candidatura/'.$id.'/aprobar', [
            'version' => $this->solicitud('candidatura', $id)->version, 'motivo' => 'No debe aprobar reevaluada',
        ])->assertRedirect()->assertSessionHasErrors('operacion');
    }

    public static function evaluacionesInvalidas(): array
    {
        return [
            'faltan criterios' => [['puntuaciones' => ['tecnico' => ['puntuacion' => 2, 'comentario' => 'Técnico']]], 'puntuaciones.blando'],
            'puntuación fuera de escala' => [['puntuaciones' => ['tecnico' => ['puntuacion' => 3, 'comentario' => 'Fuera de escala'], 'blando' => ['puntuacion' => 1, 'comentario' => 'Blando'], 'academico' => ['puntuacion' => 2, 'comentario' => 'Académico']]], 'puntuaciones.tecnico.puntuacion'],
            'puntuación booleana' => [['puntuaciones' => ['tecnico' => ['puntuacion' => true, 'comentario' => 'No es un entero'], 'blando' => ['puntuacion' => 1, 'comentario' => 'Blando'], 'academico' => ['puntuacion' => 2, 'comentario' => 'Académico']]], 'puntuaciones.tecnico.puntuacion'],
            'comentario general vacío' => [['comentarios' => '  '], 'comentarios'],
            'recomendación inválida' => [['recomendada' => 'tal vez'], 'recomendada'],
            'actor empresarial forjado' => [['representante_id' => -220006], 'representante_id'],
        ];
    }

    #[DataProvider('evaluacionesInvalidas')]
    public function test_rubrica_invalida_no_cambia_estado_ni_crea_evaluaciones(array $cambio, string $campo): void
    {
        $this->entrar();
        $id = $this->enviar();
        $this->entrar('empresa');
        $this->post('/participacion/candidatura/'.$id.'/evaluar',
            array_merge(['version' => $this->solicitud('candidatura', $id)->version], $this->rubrica($cambio)))
            ->assertRedirect()->assertSessionHasErrors($campo);
        $actual = $this->solicitud('candidatura', $id);
        $this->assertSame('pendiente_evaluacion', $actual->solicitud->estado);
        $this->assertSame([], $actual->evaluaciones);
    }

    public function test_evaluacion_con_formulario_obsoleto_no_sobrescribe_la_nueva(): void
    {
        $this->entrar();
        $id = $this->enviar();
        $this->entrar('empresa');
        $version = $this->solicitud('candidatura', $id)->version;
        $this->operar('candidatura', $id, 'evaluar', $this->rubrica());
        $this->post('/participacion/candidatura/'.$id.'/evaluar', array_merge(['version' => $version], $this->rubrica(['comentarios' => 'No sobrescribir'])))
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertCount(1, $this->solicitud('candidatura', $id)->evaluaciones);
    }

    public function test_empresa_ve_datos_permitidos_del_candidato_sin_identificadores_reservados(): void
    {
        $this->entrar();
        $id = $this->enviar();
        $this->entrar('empresa');
        $respuesta = $this->get('/participacion/candidatura/'.$id)->assertOk();
        $dto = json_encode($respuesta->viewData('detalle'), JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
        foreach (['Formación académica WEB06', 'alumno-contacto-web06@example.invalid', 'Intermedio', 'Texto de evidencia WEB06'] as $publico) {
            $this->assertStringContainsString($publico, $dto);
        }
        foreach (['WEB06-ALUMNO-PROPIO', 'web02-alumno@example.invalid', 'hash_contrasena', 'correo_normalizado', 'requiere_cambio_clave'] as $privado) {
            $this->assertStringNotContainsString($privado, $dto);
            $respuesta->assertDontSee($privado);
        }
        $respuesta->assertDontSee('href="javascript:', false)->assertDontSee('src="javascript:', false);
        // UX-02: la ayuda compara con las habilidades del proyecto propio sin ampliar datos visibles.
        $this->assertArrayHasKey('coincidencia', $respuesta->original->getData());
        $coincidencia = $respuesta->viewData('coincidencia');
        if ($coincidencia !== null) {
            $this->assertLessThanOrEqual($coincidencia->requeridas, $coincidencia->cumplidas);
        }
        $this->entrar();
        $this->assertNull($this->get('/participacion/candidatura/'.$id)->assertOk()->viewData('coincidencia'));
    }

    public function test_empresa_compara_candidato_con_habilidades_de_la_version_publicada(): void
    {
        $this->entrar();
        $id = $this->enviar('candidatura', -250201);
        $this->entrar('empresa');
        $respuesta = $this->get('/participacion/candidatura/'.$id)->assertOk();
        $coincidencia = $respuesta->viewData('coincidencia');
        // El alumno de esta fixture registró la habilidad requerida por la versión publicada.
        $this->assertSame([1, 1, []], [$coincidencia->requeridas, $coincidencia->cumplidas, $coincidencia->faltantes]);
        $respuesta->assertSee('Cumple 1 de 1')->assertSee('Habilidades frente al proyecto');
    }

    public function test_d11_empresa_descarga_cv_del_postulante_y_otra_empresa_no(): void
    {
        Storage::fake('local');
        $this->entrar();
        $this->post('/perfil/documentos', ['tipo' => 'curriculum', 'archivo' => UploadedFile::fake()->createWithContent('CV alumno.pdf', "%PDF-1.4\n%%EOF\n")])
            ->assertSessionHasNoErrors();
        $id = $this->enviar();
        $this->entrar('empresa');
        $respuesta = $this->get('/participacion/candidatura/'.$id)->assertOk()->assertSee('CV alumno.pdf');
        $cv = collect($respuesta->viewData('documentos'))->flatten(1)->firstWhere('tipo', 'curriculum');
        $this->get('/documentos/'.$cv->id)->assertOk()->assertHeader('X-Content-Type-Options', 'nosniff');
        $this->entrar('otra-empresa');
        $this->get('/documentos/'.$cv->id)->assertNotFound();
    }

    public function test_otra_empresa_no_ve_ni_evalua_candidatura_ajena(): void
    {
        $this->entrar();
        $id = $this->enviar();
        $this->entrar('otra-empresa');
        $this->get('/participacion/candidatura/'.$id)->assertForbidden();
        $this->post('/participacion/candidatura/'.$id.'/evaluar', array_merge(['version' => str_repeat('a', 64)], $this->rubrica()))->assertForbidden();
        $this->assertSame(0, $this->listado('candidatura')->total());
    }

    public function test_otro_alumno_no_lee_ni_cancela_solicitud_ajena(): void
    {
        $this->entrar();
        $id = $this->enviar();
        $this->entrar('web06-alumno-1@example.invalid');
        $this->get('/participacion/candidatura/'.$id)->assertForbidden();
        $this->post('/participacion/candidatura/'.$id.'/cancelar', ['version' => str_repeat('a', 64)])->assertForbidden();
    }

    public function test_empresa_y_profesor_no_resuelven_asignaciones(): void
    {
        $this->entrar();
        $id = $this->enviar();
        $this->entrar('empresa');
        $this->post('/participacion/candidatura/'.$id.'/aprobar', ['version' => $this->solicitud('candidatura', $id)->version, 'motivo' => 'Inyección'])
            ->assertForbidden();
        $this->entrar('profesor');
        $this->post('/seguimiento/proyectos/-260201/iniciar', ['version' => str_repeat('a', 64)])->assertForbidden();
    }

    public function test_rechazo_admin_con_motivo_conserva_historia_y_libera_candidatura(): void
    {
        $this->entrar();
        $id = $this->enviar();
        $this->entrar('admin');
        $this->operar('candidatura', $id, 'rechazar', ['motivo' => 'Perfil no corresponde a los requisitos WEB06']);
        $this->entrar();
        $rechazo = $this->solicitud('candidatura', $id);
        $this->assertSame('rechazada', $rechazo->solicitud->estado);
        $this->assertNotEmpty($rechazo->decisiones);
        $this->assertNotContains('cancelar', $rechazo->acciones);
        $this->assertNotSame($id, $this->enviar());
    }

    public function test_admin_exige_motivo_y_cas_para_resolver(): void
    {
        $this->entrar('profesor');
        $id = $this->enviar('direccion');
        $this->entrar('admin');
        $version = $this->solicitud('direccion', $id)->version;
        $this->post('/participacion/direccion/'.$id.'/aprobar', ['version' => $version, 'motivo' => '  '])
            ->assertRedirect()->assertSessionHasErrors('motivo');
        $this->operar('direccion', $id, 'aprobar', ['motivo' => 'Dirección pertinente WEB06']);
        $this->post('/participacion/direccion/'.$id.'/rechazar', ['version' => $version, 'motivo' => 'Decisión antigua'])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame('aprobada', $this->solicitud('direccion', $id)->solicitud->estado);
    }

    public function test_alumno_asignado_no_se_retira_unilateralmente_y_aun_puede_postularse(): void
    {
        $id = $this->asignarAlumno();
        $this->entrar();
        $this->post('/participacion/candidatura/'.$id.'/cancelar', ['version' => $this->solicitud('candidatura', $id)->version])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $otro = $this->enviar('candidatura', -260202);
        $this->evaluar($otro);
        $this->preseleccionar($otro);
        $this->entrar('admin');
        $this->post('/participacion/candidatura/'.$otro.'/aprobar', ['version' => $this->solicitud('candidatura', $otro)->version, 'motivo' => 'No debe exceder carga'])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame('preseleccionada', $this->solicitud('candidatura', $otro)->solicitud->estado);
    }

    public function test_proyecto_con_una_plaza_no_admite_segunda_asignacion(): void
    {
        $this->asignarAlumno(-260224);
        $this->entrar('web06-alumno-1@example.invalid');
        $id = $this->enviar('candidatura', -260224);
        $this->evaluar($id);
        $this->preseleccionar($id);
        $this->entrar('admin');
        $this->post('/participacion/candidatura/'.$id.'/aprobar', ['version' => $this->solicitud('candidatura', $id)->version, 'motivo' => 'No debe exceder cupo'])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame('preseleccionada', $this->solicitud('candidatura', $id)->solicitud->estado);
    }

    public function test_evaluadas_y_preseleccionadas_cuentan_y_aprobar_libera_sin_cancelar_otras(): void
    {
        $this->entrar();
        $primera = $this->enviar('candidatura', -260201);
        $segunda = $this->enviar('candidatura', -260202);
        $tercera = $this->enviar('candidatura', -260203);
        $this->evaluar($primera);
        $this->preseleccionar($primera);
        $this->entrar();
        $this->post('/catalogo/-260204/participar', ['version' => $this->contexto(-260204)->version])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->aprobar('candidatura', $primera);
        $this->entrar();
        $this->assertSame('pendiente_evaluacion', $this->solicitud('candidatura', $segunda)->solicitud->estado);
        $this->assertSame('pendiente_evaluacion', $this->solicitud('candidatura', $tercera)->solicitud->estado);
        $cuarta = $this->enviar('candidatura', -260204);
        $this->assertSame('pendiente_evaluacion', $this->solicitud('candidatura', $cuarta)->solicitud->estado);
    }

    public function test_profesor_no_tiene_cuarta_direccion_ni_retiro_unilateral(): void
    {
        $primera = null;
        foreach ([-260201, -260202, -260203] as $proyecto) {
            $id = $this->asignarProfesor($proyecto);
            $primera ??= $id;
        }
        $this->entrar('profesor');
        $this->post('/participacion/direccion/'.$primera.'/cancelar', ['version' => $this->solicitud('direccion', $primera)->version])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $cuarta = $this->enviar('direccion', -260204);
        $this->entrar('admin');
        $this->post('/participacion/direccion/'.$cuarta.'/aprobar', ['version' => $this->solicitud('direccion', $cuarta)->version, 'motivo' => 'No debe exceder carga docente'])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame('pendiente', $this->solicitud('direccion', $cuarta)->solicitud->estado);
    }

    public function test_solo_un_director_vigente_por_proyecto(): void
    {
        $this->asignarProfesor();
        $this->entrar('web06-profesor-1@example.invalid');
        $id = $this->enviar('direccion');
        $this->entrar('admin');
        $this->post('/participacion/direccion/'.$id.'/aprobar', ['version' => $this->solicitud('direccion', $id)->version, 'motivo' => 'No debe duplicar dirección'])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame('pendiente', $this->solicitud('direccion', $id)->solicitud->estado);
    }

    public function test_inicio_exige_minimo_autorizado_pero_no_llenar_cupo(): void
    {
        $this->entrar('admin');
        $this->post('/seguimiento/proyectos/-260201/iniciar', ['version' => $this->proyectos(-260201)->version])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->asignarAlumno();
        $this->asignarProfesor();
        $this->ciclo(-260201, 'iniciar');
        $this->assertSame('en_curso', $this->proyectos(-260201)->proyecto->estado);
        $this->entrar();
        $this->get('/catalogo/-260201')->assertNotFound();
        $this->get('/seguimiento/proyectos/-260201')->assertOk();
    }

    public function test_cierre_cancelado_cierra_pendientes_y_preserva_detalles_propios(): void
    {
        $this->entrar();
        $alumno = $this->enviar();
        $this->entrar('profesor');
        $profesor = $this->enviar('direccion');
        $this->entrar('admin');
        $this->ciclo(-260201, 'cancelar', ['motivo' => 'La empresa ya no requiere el proyecto WEB06']);
        $this->assertSame('cancelado', $this->proyectos(-260201)->proyecto->estado);
        $this->entrar();
        $this->assertSame('cancelada', $this->solicitud('candidatura', $alumno)->solicitud->estado);
        $this->get('/catalogo/-260201')->assertNotFound();
        $this->entrar('profesor');
        $this->assertSame('cancelada', $this->solicitud('direccion', $profesor)->solicitud->estado);
    }

    public function test_retirar_director_pausa_conserva_alumnos_y_permite_reposicion_minima(): void
    {
        $alumno = $this->asignarAlumno();
        $director = $this->asignarProfesor();
        $this->ciclo(-260201, 'iniciar');
        $datos = $this->proyectos(-260201);
        $asignacion = $datos->directores[0]->id;
        $this->ciclo(-260201, 'retirar_director', ['asignacion_id' => $asignacion, 'motivo' => 'Relevo académico WEB06']);
        $pausado = $this->proyectos(-260201);
        $this->assertSame('pausado', $pausado->proyecto->estado);
        $this->assertSame('vigente', $pausado->alumnos[0]->estado);
        $this->assertSame('revocada', $this->solicitud('direccion', $director)->asignacion->estado);
        $this->assertSame('vigente', $this->solicitud('candidatura', $alumno)->asignacion->estado);

        $this->entrar('web06-profesor-1@example.invalid');
        $lista = $this->get('/seguimiento/proyectos?estado=pausado')->assertOk()->viewData('proyectos');
        $this->assertContains(-260201, array_map(fn ($p) => $p->id, $lista->items()));
        $this->assertTrue($this->proyectos(-260201)->vacante);
        $nuevo = $this->enviar('direccion');
        $this->aprobar('direccion', $nuevo);
        $this->assertSame('pausado', $this->proyectos(-260201)->proyecto->estado);
        $this->ciclo(-260201, 'reanudar');
        $this->assertSame('en_curso', $this->proyectos(-260201)->proyecto->estado);
    }

    public function test_retirar_ultimo_alumno_pausa_sin_perder_director_y_repone_solo_alumno(): void
    {
        $this->asignarAlumno();
        $this->asignarProfesor();
        $this->ciclo(-260201, 'iniciar');
        $datos = $this->proyectos(-260201);
        $this->ciclo(-260201, 'retirar_alumno', ['asignacion_id' => $datos->alumnos[0]->id, 'motivo' => 'Retiro justificado WEB06']);
        $pausado = $this->proyectos(-260201);
        $this->assertSame('pausado', $pausado->proyecto->estado);
        $this->assertSame('vigente', $pausado->directores[0]->estado);
        $this->entrar('web06-profesor-1@example.invalid');
        $this->get('/catalogo/-260201/participar')->assertNotFound();
        $this->entrar('web06-alumno-1@example.invalid');
        $this->assertTrue($this->proyectos(-260201)->vacante);
        $nuevo = $this->enviar();
        $this->evaluar($nuevo);
        $this->preseleccionar($nuevo);
        $this->aprobar('candidatura', $nuevo);
        $this->assertSame('pausado', $this->proyectos(-260201)->proyecto->estado);
        $this->ciclo(-260201, 'reanudar');
        $this->assertSame('en_curso', $this->proyectos(-260201)->proyecto->estado);
    }

    public function test_director_ve_alumno_asignado_sin_matricula_ni_evaluacion_privada(): void
    {
        $candidatura = $this->asignarAlumno();
        $this->asignarProfesor();
        $this->entrar('profesor');
        $respuesta = $this->get('/seguimiento/proyectos/-260201')->assertOk();
        $dto = json_encode($respuesta->viewData('detalle'), JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
        $this->assertStringContainsString('alumno-contacto-web06@example.invalid', $dto);
        foreach (['WEB06-ALUMNO-PROPIO', 'web02-alumno@example.invalid', 'Evaluación general privada de la empresa WEB06', 'puntuacion', 'hash_contrasena'] as $privado) {
            $this->assertStringNotContainsString($privado, $dto);
        }
        $this->get('/participacion/candidatura/'.$candidatura)->assertForbidden();
    }

    public function test_no_se_reciben_incorporaciones_generales_en_curso(): void
    {
        $this->asignarAlumno();
        $this->asignarProfesor();
        $this->ciclo(-260201, 'iniciar');
        $this->entrar('web06-alumno-1@example.invalid');
        $this->get('/catalogo/-260201/participar')->assertNotFound();
        $this->post('/catalogo/-260201/participar', ['version' => str_repeat('a', 64)])
            ->assertNotFound();
        $this->assertSame(0, $this->listado('candidatura')->total());
    }

    public function test_finalizar_solo_desde_en_curso_y_no_reabrir(): void
    {
        $this->entrar('admin');
        $this->post('/seguimiento/proyectos/-260201/finalizar', ['version' => $this->proyectos(-260201)->version, 'motivo' => 'No debe finalizar publicado'])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->asignarAlumno();
        $this->asignarProfesor();
        $this->ciclo(-260201, 'iniciar');
        $this->ciclo(-260201, 'finalizar', ['motivo' => 'Objetivos cumplidos WEB06']);
        $this->assertSame('finalizado', $this->proyectos(-260201)->proyecto->estado);
        $this->assertSame('finalizada', $this->proyectos(-260201)->alumnos[0]->estado);
        $this->assertSame('finalizada', $this->proyectos(-260201)->directores[0]->estado);
        $this->post('/seguimiento/proyectos/-260201/reanudar', ['version' => $this->proyectos(-260201)->version])
            ->assertRedirect()->assertSessionHasErrors('operacion');
    }

    public function test_formulario_de_ciclo_obsoleto_no_decide_sobre_otro_estado(): void
    {
        $this->entrar('admin');
        $version = $this->proyectos(-260201)->version;
        $this->asignarAlumno();
        $this->asignarProfesor();
        $this->post('/seguimiento/proyectos/-260201/cancelar', ['version' => $version, 'motivo' => 'Decisión obsoleta'])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame('publicado', $this->proyectos(-260201)->proyecto->estado);
    }

    public function test_retiro_rechaza_identificador_booleano_sin_modificar_proyecto(): void
    {
        $this->entrar('admin');
        $this->post('/seguimiento/proyectos/-260201/retirar_alumno', [
            'version' => $this->proyectos(-260201)->version, 'asignacion_id' => true, 'motivo' => 'Identificador no válido',
        ])->assertRedirect()->assertSessionHasErrors('asignacion_id');
        $this->assertSame('publicado', $this->proyectos(-260201)->proyecto->estado);
    }

    public function test_historial_propio_paginado_y_filtro_por_estado(): void
    {
        $this->entrar('web06-historial@example.invalid');
        $primera = $this->listado('candidatura');
        $segunda = $this->listado('candidatura', '?page=2');
        $this->assertSame(22, $primera->total());
        $this->assertSame(20, $primera->count());
        $this->assertSame(2, $segunda->count());
        $ids = fn ($p) => array_map(fn ($row) => $row->id, $p->items());
        $this->assertSame([], array_values(array_intersect($ids($primera), $ids($segunda))));
        $this->assertSame(22, $this->listado('candidatura', '?estado=cancelada')->total());
        $this->assertSame(0, $this->listado('candidatura', '?estado=pendiente_evaluacion')->total());
    }

    public function test_csrf_real_rechaza_envio_sin_token_y_admite_token_valido(): void
    {
        $this->entrar();
        $datos = ['version' => $this->contexto(-260201)->version];
        $this->app->bind(PreventRequestForgery::class, CsrfActivoEnParticipacion::class);
        $this->post('/catalogo/-260201/participar', $datos)->assertStatus(419);
        $this->assertSame(0, $this->listado('candidatura')->total());
        $this->post('/catalogo/-260201/participar', $datos + ['_token' => session()->token()])
            ->assertRedirect()->assertSessionHasNoErrors();
        $this->assertSame(1, $this->listado('candidatura')->total());
    }

    public static function actoresConFallo(): array
    {
        return ['auditoría' => ['web06-auditoria@example.invalid'], 'aviso' => ['web06-aviso@example.invalid']];
    }

    #[DataProvider('actoresConFallo')]
    public function test_fallo_en_auditoria_o_aviso_revierte_el_envio(string $correo): void
    {
        $this->entrar($correo);
        $this->post('/catalogo/-260201/participar', ['version' => $this->contexto(-260201)->version])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame(0, $this->listado('candidatura')->total());
    }

    public function test_cuenta_sin_perfil_no_envia_una_candidatura_incompleta(): void
    {
        $this->entrar('web06-sin-perfil@example.invalid');
        $respuesta = $this->get('/catalogo/-260201/participar');
        $this->assertContains($respuesta->getStatusCode(), [200, 302]);
        $version = $respuesta->getStatusCode() === 200 ? $respuesta->viewData('contexto')->version : str_repeat('a', 64);
        $this->post('/catalogo/-260201/participar', ['version' => $version])
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $this->assertSame(0, $this->listado('candidatura')->total());
    }

    public function test_invitados_y_claves_temporales_no_entran_a_participacion(): void
    {
        foreach (['/catalogo/-260201/participar', '/participacion/candidatura', '/participacion/direccion', '/seguimiento/proyectos'] as $ruta) {
            $this->get($ruta)->assertRedirect('/login');
        }
        $this->post('/catalogo/-260201/participar', ['version' => str_repeat('a', 64)])->assertRedirect('/login');
        $this->post('/login', ['correo' => 'web02-temporal@example.invalid', 'password' => self::PASSWORD])->assertRedirect('/clave');
        $this->get('/participacion/candidatura')->assertRedirect('/clave');
        $this->get('/seguimiento/proyectos')->assertRedirect('/clave');
    }

    public static function bandejasAjenaAlRol(): array
    {
        return ['alumno sin dirección' => ['alumno', 'direccion'], 'profesor sin candidaturas' => ['profesor', 'candidatura'],
            'empresa sin dirección docente' => ['empresa', 'direccion']];
    }

    #[DataProvider('bandejasAjenaAlRol')]
    public function test_cada_rol_consulta_solo_la_bandeja_que_le_corresponde(string $rol, string $tipo): void
    {
        $this->entrar($rol);
        $this->get('/participacion/'.$tipo)->assertForbidden();
    }

    public static function filtrosInvalidos(): array
    {
        return ['búsqueda como arreglo' => ['buscar[]=x', 'buscar'], 'página inválida' => ['page=0', 'page'],
            'estado desconocido' => ['estado=aprobada_por_empresa', 'estado'], 'estado como arreglo' => ['estado[]=pendiente', 'estado']];
    }

    #[DataProvider('filtrosInvalidos')]
    public function test_filtros_malformados_no_generan_errores_internos(string $filtro, string $campo): void
    {
        $this->entrar();
        $this->get('/participacion/candidatura?'.$filtro)->assertRedirect()->assertSessionHasErrors($campo);
    }

    public function test_cuenta_inactiva_no_inicia_sesion_ni_envia(): void
    {
        $this->post('/login', ['correo' => 'web02-inactivo@example.invalid', 'password' => self::PASSWORD])
            ->assertRedirect()->assertSessionHasErrors('correo');
        $this->post('/catalogo/-260201/participar', ['version' => str_repeat('a', 64)])->assertRedirect('/login');
    }

    public static function rutasInvalidas(): array
    {
        return ['tipo inventado' => ['/participacion/secreto'], 'id inexistente' => ['/participacion/candidatura/-999999999'],
            'id fuera de rango' => ['/participacion/candidatura/999999999999999999999999'],
            'proyecto inexistente' => ['/catalogo/-999999999/participar']];
    }

    #[DataProvider('rutasInvalidas')]
    public function test_recursos_inexistentes_no_filtran_datos(string $ruta): void
    {
        $this->entrar();
        $this->get($ruta)->assertNotFound();
    }
}
