<?php

namespace Tests\Integration;

use DOMDocument;
use DOMXPath;
use Illuminate\Foundation\Http\Middleware\PreventRequestForgery;
use Illuminate\Http\UploadedFile;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\PostgresTestCase;
use Throwable;

class CsrfActivoEnPerfiles extends PreventRequestForgery
{
    protected function runningUnitTests()
    {
        return false;
    }
}

class PerfilesCatalogoTest extends PostgresTestCase
{
    private const PASSWORD = 'PruebaSegura-2026!';

    protected function setUp(): void
    {
        parent::setUp();
        if (! getenv('BANCO_TEST_WEB05')) {
            $this->markTestSkipped('Ejecuta python tests/perfiles.py para la integración WEB-05.');
        }
    }

    public function call($method, $uri, $parameters = [], $cookies = [], $files = [], $server = [], $content = null)
    {
        $conexion = DB::connection('pgsql');
        $nivel = $conexion->transactionLevel();
        if ($nivel === 0) {
            return parent::call($method, $uri, $parameters, $cookies, $files, $server, $content);
        }
        // Cada petición conserva el comportamiento autocommit de producción
        // ante errores SQL; la transacción exterior aísla el caso completo.
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

    private function entrar(string $rol = 'alumno'): void
    {
        $this->post('/login', ['correo' => 'web02-'.$rol.'@example.invalid', 'password' => self::PASSWORD])
            ->assertRedirect('/panel');
    }

    private function perfil(): object
    {
        $respuesta = $this->get('/perfil')->assertOk();
        $this->assertMatchesRegularExpression('/\A[a-f0-9]{64}\z/', $respuesta->viewData('version'));

        return (object) [
            'perfil' => $respuesta->viewData('perfil'),
            'habilidades' => $respuesta->viewData('habilidadesPerfil'),
            'version' => $respuesta->viewData('version'),
        ];
    }

    private function datosAlumno(array $cambio = []): array
    {
        return array_replace([
            'matricula' => 'WEB05-PROPIO-001', 'carrera' => 'Sistemas computacionales', 'semestre' => 5,
            'datos_academicos' => 'Materias de bases de datos y desarrollo web.',
            'contacto_correo' => 'contacto-alumno-web05@example.invalid', 'contacto_telefono' => '5550103030',
            'habilidades_seleccionadas' => [], 'version' => $this->perfil()->version,
        ], $cambio);
    }

    private function datosProfesor(array $cambio = []): array
    {
        return array_replace([
            'numero_empleado' => 'WEB05-PROF-PROPIO', 'especialidad' => 'Bases de datos',
            'experiencia' => 'Dirección de proyectos académicos.',
            'contacto_correo' => 'contacto-profesor-web05@example.invalid', 'contacto_telefono' => '5550104040',
            'version' => $this->perfil()->version,
        ], $cambio);
    }

    private function listado(string $query = ''): LengthAwarePaginator
    {
        $respuesta = $this->get('/catalogo'.$query)->assertOk();
        $paginador = $respuesta->viewData('proyectos');
        $this->assertInstanceOf(LengthAwarePaginator::class, $paginador);

        return $paginador;
    }

    private function ids(LengthAwarePaginator $proyectos): array
    {
        return array_map(fn ($p) => (int) $p->id, $proyectos->items());
    }

    public function test_alumno_sin_perfil_puede_crearlo_y_editarlo_sin_alterar_su_cuenta(): void
    {
        $this->entrar();
        $inicial = $this->perfil();
        $this->assertNull($inicial->perfil);
        $datos = $this->datosAlumno();
        $this->put('/perfil', $datos)->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $creado = $this->perfil();
        $this->assertSame($datos['matricula'], $creado->perfil->matricula);
        $this->assertSame($datos['contacto_correo'], $creado->perfil->contacto_correo);
        $this->assertNotSame($inicial->version, $creado->version);
        $this->put('/perfil', array_replace($datos, ['carrera' => 'Ingeniería de software', 'version' => $creado->version]))
            ->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $this->assertSame('Ingeniería de software', $this->perfil()->perfil->carrera);
        $this->post('/logout')->assertRedirect();
        $this->entrar();
        $this->get('/panel')->assertOk();
    }

    public function test_profesor_crea_y_edita_su_perfil_sin_habilidades_estructuradas(): void
    {
        $this->entrar('profesor');
        $this->assertNull($this->perfil()->perfil);
        $datos = $this->datosProfesor();
        $this->put('/perfil', $datos)->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $perfil = $this->perfil();
        $this->assertSame($datos['numero_empleado'], $perfil->perfil->numero_empleado);
        $this->assertSame([], $perfil->habilidades);
        $this->put('/perfil', array_replace($datos, ['especialidad' => 'Desarrollo de software', 'version' => $perfil->version]))
            ->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $this->assertSame('Desarrollo de software', $this->perfil()->perfil->especialidad);
    }

    public function test_habilidades_duras_y_blandas_conservan_nivel_descripcion_y_evidencia_textual(): void
    {
        $this->entrar();
        $this->put('/perfil', $this->datosAlumno([
            'habilidades_seleccionadas' => [-250101, -250102],
            'niveles' => [-250101 => 'Intermedio: consultas y transacciones', -250102 => 'Trabajo en grupos pequeños'],
            'descripciones' => [-250101 => 'Diseño de bases de datos', -250102 => 'Presentaciones de clase'],
            'evidencias' => [-250101 => 'https://example.invalid/portafolio', -250102 => 'Exposición del proyecto final'],
        ]))->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $habilidades = collect($this->perfil()->habilidades)->keyBy('habilidad_id');
        $this->assertCount(2, $habilidades);
        $this->assertSame('dura', $habilidades[-250101]->tipo);
        $this->assertSame('blanda', $habilidades[-250102]->tipo);
        $this->assertSame('Intermedio: consultas y transacciones', $habilidades[-250101]->nivel_dominio);
        $this->assertSame('Diseño de bases de datos', $habilidades[-250101]->descripcion);
        $this->assertSame('https://example.invalid/portafolio', $habilidades[-250101]->evidencia);
        $this->assertSame('Exposición del proyecto final', $habilidades[-250102]->evidencia);
    }

    public function test_editar_y_quitar_habilidades_reemplaza_el_conjunto_sin_duplicados(): void
    {
        $this->entrar();
        $this->put('/perfil', $this->datosAlumno(['habilidades_seleccionadas' => [-250101, -250102]]))
            ->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $this->put('/perfil', $this->datosAlumno([
            'habilidades_seleccionadas' => [-250102], 'niveles' => [-250102 => 'Avanzado textual'],
        ]))->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $habilidades = $this->perfil()->habilidades;
        $this->assertCount(1, $habilidades);
        $this->assertSame(-250102, (int) $habilidades[0]->habilidad_id);
        $this->assertSame('Avanzado textual', $habilidades[0]->nivel_dominio);
        $this->put('/perfil', $this->datosAlumno())->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $this->assertSame([], $this->perfil()->habilidades);
    }

    public function test_desmarcar_todas_se_conserva_tras_error_y_permite_quitarlas_al_corregir(): void
    {
        $this->entrar();
        $this->put('/perfil', $this->datosAlumno(['habilidades_seleccionadas' => [-250101, -250102]]))
            ->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $datos = $this->datosAlumno(['carrera' => 'Nueva carrera WEB05 sin habilidades', 'semestre' => 0]);
        // Un formulario HTML omite la clave cuando todas las casillas quedan
        // desmarcadas; enviar [] no reproduce ese comportamiento del navegador.
        unset($datos['habilidades_seleccionadas']);
        $this->from('/perfil')->put('/perfil', $datos)->assertRedirect('/perfil')->assertSessionHasErrors('semestre');
        $respuesta = $this->withCookie(config('session.cookie'), session()->getId())->get('/perfil')->assertOk();
        $this->assertCount(2, $respuesta->viewData('habilidadesPerfil'));

        $documento = new DOMDocument;
        $this->assertTrue($documento->loadHTML($respuesta->getContent(), LIBXML_NONET | LIBXML_NOERROR | LIBXML_NOWARNING));
        $campos = new DOMXPath($documento);
        $this->assertGreaterThanOrEqual(2, $campos->query('//input[@name="habilidades_seleccionadas[]"]')->length);
        $this->assertSame(0, $campos->query('//input[@name="habilidades_seleccionadas[]"][@checked]')->length);
        $this->assertSame($datos['carrera'], $campos->evaluate('string(//input[@name="carrera"]/@value)'));
        $this->assertSame('0', $campos->evaluate('string(//input[@name="semestre"]/@value)'));
        $this->assertSame($datos['version'], $campos->evaluate('string(//input[@name="version"]/@value)'));

        $datos['semestre'] = 6;
        $this->put('/perfil', $datos)->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $guardado = $this->perfil();
        $this->assertSame([], $guardado->habilidades);
        $this->assertSame($datos['carrera'], $guardado->perfil->carrera);
        $this->assertSame(6, $guardado->perfil->semestre);
    }

    public function test_version_obsoleta_no_sobrescribe_perfil_ni_habilidades(): void
    {
        $this->entrar();
        $viejos = $this->datosAlumno();
        $this->put('/perfil', array_replace($viejos, ['carrera' => 'Edición vigente', 'habilidades_seleccionadas' => [-250102]]))
            ->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $antes = $this->perfil();
        $this->put('/perfil', array_replace($viejos, ['carrera' => 'Edición obsoleta', 'habilidades_seleccionadas' => [-250101]]))
            ->assertRedirect()->assertSessionHasErrors('operacion');
        $despues = $this->perfil();
        $this->assertEquals($antes, $despues);
    }

    public function test_habilidad_inexistente_revierte_cambio_academico_y_habilidades(): void
    {
        $this->entrar();
        $this->put('/perfil', $this->datosAlumno(['habilidades_seleccionadas' => [-250102]]))
            ->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $antes = $this->perfil();
        $this->put('/perfil', $this->datosAlumno(['carrera' => 'No debe guardarse', 'habilidades_seleccionadas' => [-999999999]]))
            ->assertRedirect()->assertSessionHasErrors('habilidades_seleccionadas');
        $this->assertEquals($antes, $this->perfil());
    }

    public static function identificadoresAjenos(): array
    {
        return [
            'matricula alta' => ['alumno', 'matricula', 'WEB05-OTRO-001', false],
            'matricula edición' => ['alumno', 'matricula', 'WEB05-OTRO-001', true],
            'empleado alta' => ['profesor', 'numero_empleado', 'WEB05-PROF-001', false],
            'empleado edición' => ['profesor', 'numero_empleado', 'WEB05-PROF-001', true],
        ];
    }

    #[DataProvider('identificadoresAjenos')]
    public function test_identificadores_unicos_no_se_apropian_de_otro_perfil(string $rol, string $campo, string $valor, bool $existente): void
    {
        $this->entrar($rol);
        $datos = $rol === 'alumno' ? $this->datosAlumno() : $this->datosProfesor();
        if ($existente) {
            $this->put('/perfil', $datos)->assertRedirect('/perfil')->assertSessionHasNoErrors();
            $datos['version'] = $this->perfil()->version;
        }
        $antes = $this->perfil();
        $this->put('/perfil', array_replace($datos, [$campo => $valor]))->assertRedirect()->assertSessionHasErrors($campo);
        $this->assertEquals($antes, $this->perfil());
    }

    public static function perfilesMinimos(): array
    {
        return ['alumno' => ['alumno', 'matricula'], 'profesor' => ['profesor', 'numero_empleado']];
    }

    #[DataProvider('perfilesMinimos')]
    public function test_datos_opcionales_pueden_omitirse_sin_inventar_contacto_de_acceso(string $rol, string $identificador): void
    {
        $this->entrar($rol);
        $this->put('/perfil', [$identificador => 'WEB05-MINIMO', 'version' => $this->perfil()->version])
            ->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $perfil = $this->perfil();
        $this->assertSame('WEB05-MINIMO', $perfil->perfil->{$identificador});
        $this->assertNull($perfil->perfil->contacto_correo);
        $this->assertNull($perfil->perfil->contacto_telefono);
        $this->assertSame([], $perfil->habilidades);
    }

    public static function datosInvalidos(): array
    {
        return [
            'matricula vacía' => [['matricula' => '  '], 'matricula'],
            'semestre cero' => [['semestre' => 0], 'semestre'],
            'semestre fracción' => [['semestre' => 1.5], 'semestre'],
            'contacto inválido' => [['contacto_correo' => 'javascript:alert(1)'], 'contacto_correo'],
            'texto como arreglo' => [['carrera' => ['ataque']], 'carrera'],
            'habilidades como texto' => [['habilidades_seleccionadas' => '1,2'], 'habilidades_seleccionadas'],
            'habilidades repetidas' => [['habilidades_seleccionadas' => [-250101, -250101]], 'habilidades_seleccionadas.0'],
            'evidencia anidada' => [['habilidades_seleccionadas' => [-250101], 'evidencias' => [-250101 => ['url' => 'x']]], 'evidencias.-250101'],
            'versión inválida' => [['version' => 'versión-inventada'], 'version'],
            'identificador ajeno' => [['usuario_id' => -250003], 'usuario_id'],
            'actor inyectado' => [['actor' => -220001], 'actor'],
            'rol inyectado' => [['rol_principal' => 'administrador'], 'rol_principal'],
            'habilidades canónicas inyectadas' => [['habilidades' => [['habilidad_id' => -250101]]], 'habilidades'],
            'campo profesor' => [['numero_empleado' => 'AJENO'], 'numero_empleado'],
        ];
    }

    #[DataProvider('datosInvalidos')]
    public function test_payload_invalido_se_rechaza_sin_crear_perfil(array $cambio, string $campo): void
    {
        $this->entrar();
        $this->put('/perfil', $this->datosAlumno($cambio))->assertRedirect()->assertSessionHasErrors($campo);
        $this->assertNull($this->perfil()->perfil);
    }

    public function test_profesor_no_recibe_habilidades_de_alumno_ni_campos_ajenos(): void
    {
        $this->entrar('profesor');
        $this->put('/perfil', $this->datosProfesor(['habilidades_seleccionadas' => [-250101], 'matricula' => 'AJENA']))
            ->assertRedirect()->assertSessionHasErrors(['habilidades_seleccionadas', 'matricula']);
        $this->assertNull($this->perfil()->perfil);
    }

    private function pdf(string $nombre = 'cv.pdf', string $contenido = "%PDF-1.4\n% prueba D-11\n%%EOF\n"): UploadedFile
    {
        return UploadedFile::fake()->createWithContent($nombre, $contenido);
    }

    public function test_d11_curriculum_pdf_se_sube_reemplaza_descarga_y_quita(): void
    {
        Storage::fake('local');
        $this->entrar();
        $this->put('/perfil', $this->datosAlumno())->assertRedirect('/perfil');
        $this->post('/perfil/documentos', ['tipo' => 'curriculum', 'archivo' => $this->pdf('Mi CV.pdf')])
            ->assertRedirect()->assertSessionHasNoErrors();
        $primero = collect($this->get('/perfil')->assertOk()->assertSee('Mi CV.pdf')->viewData('documentos'))->firstWhere('tipo', 'curriculum');
        $this->assertCount(1, Storage::disk('local')->files('documentos'));

        $descarga = $this->get('/documentos/'.$primero->id)->assertOk();
        $this->assertStringStartsWith('attachment;', $descarga->headers->get('Content-Disposition'));
        $this->assertSame('nosniff', $descarga->headers->get('X-Content-Type-Options'));

        // Reemplazar conserva el archivo anterior pero solo deja vigente el nuevo.
        $this->post('/perfil/documentos', ['tipo' => 'curriculum', 'archivo' => $this->pdf('CV 2026.pdf')])->assertSessionHasNoErrors();
        $vigentes = collect($this->get('/perfil')->assertOk()->viewData('documentos'))->where('tipo', 'curriculum');
        $this->assertSame(['CV 2026.pdf'], $vigentes->pluck('nombre_original')->values()->all());
        $this->get('/documentos/'.$primero->id)->assertNotFound();
        $this->assertCount(2, Storage::disk('local')->files('documentos'));

        $this->delete('/perfil/documentos/'.$vigentes->first()->id)->assertRedirect();
        $this->assertSame([], $this->get('/perfil')->assertOk()->viewData('documentos'));
    }

    public function test_d11_rechaza_archivos_que_no_son_pdf_aunque_digan_serlo(): void
    {
        Storage::fake('local');
        $this->entrar();
        $this->post('/perfil/documentos', ['tipo' => 'curriculum', 'archivo' => $this->pdf('falso.pdf', '<html>no es pdf</html>')])
            ->assertSessionHasErrors('archivo');
        $this->post('/perfil/documentos', ['tipo' => 'curriculum', 'archivo' => UploadedFile::fake()->create('grande.pdf', 6000, 'application/pdf')])
            ->assertSessionHasErrors('archivo');
        $this->post('/perfil/documentos', ['tipo' => 'curriculum', 'archivo' => UploadedFile::fake()->createWithContent('cv.docx', 'PK')])
            ->assertSessionHasErrors('archivo');
        $this->assertSame([], Storage::disk('local')->files('documentos'));
    }

    public function test_d11_evidencia_exige_habilidad_del_perfil_y_maximo_tres(): void
    {
        Storage::fake('local');
        $this->entrar();
        $this->put('/perfil', $this->datosAlumno(['habilidades_seleccionadas' => [-250101]]))->assertRedirect('/perfil');
        $this->post('/perfil/documentos', ['tipo' => 'evidencia', 'habilidad_id' => -250102, 'archivo' => $this->pdf()])
            ->assertSessionHasErrors('archivo');
        foreach ([1, 2, 3] as $n) {
            $this->post('/perfil/documentos', ['tipo' => 'evidencia', 'habilidad_id' => -250101, 'archivo' => $this->pdf("constancia $n.pdf")])
                ->assertSessionHasNoErrors();
        }
        $this->post('/perfil/documentos', ['tipo' => 'evidencia', 'habilidad_id' => -250101, 'archivo' => $this->pdf('cuarta.pdf')])
            ->assertSessionHasErrors('archivo');
        // El archivo rechazado por la base no queda huérfano.
        $this->assertCount(3, Storage::disk('local')->files('documentos'));
        $this->assertCount(3, $this->get('/perfil')->assertOk()->viewData('documentos'));
    }

    public function test_d11_otros_usuarios_no_descargan_ni_quitan_documentos_ajenos(): void
    {
        Storage::fake('local');
        $this->entrar();
        $this->post('/perfil/documentos', ['tipo' => 'curriculum', 'archivo' => $this->pdf()])->assertSessionHasNoErrors();
        $id = collect($this->get('/perfil')->viewData('documentos'))->first()->id;
        $this->post('/logout');
        $this->get('/documentos/'.$id)->assertRedirect('/login');

        $this->entrar('profesor');
        $this->get('/documentos/'.$id)->assertNotFound();
        $this->delete('/perfil/documentos/'.$id)->assertNotFound();
        $this->get('/documentos/999999999')->assertNotFound();
    }

    public function test_formulario_de_perfil_no_acepta_archivos_fuera_de_documentos(): void
    {
        $this->entrar();
        $this->put('/perfil', $this->datosAlumno(['evidencia_archivo' => UploadedFile::fake()->create('evidencia.pdf', 2, 'application/pdf')]))
            ->assertRedirect()->assertSessionHasErrors('archivos');
        $this->assertNull($this->perfil()->perfil);
    }

    public function test_texto_html_y_url_javascript_se_muestran_escapados_y_sin_enlace_ejecutable(): void
    {
        $this->entrar();
        $ataque = '<script>alert("WEB05-XSS")</script>';
        $this->put('/perfil', $this->datosAlumno([
            'datos_academicos' => $ataque, 'habilidades_seleccionadas' => [-250101],
            'evidencias' => [-250101 => 'javascript:alert("WEB05-EVIDENCIA")'],
        ]))->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $respuesta = $this->get('/perfil')->assertOk();
        $respuesta->assertSee($ataque)->assertDontSee($ataque, false)
            ->assertDontSee('href="javascript:', false)->assertDontSee('src="javascript:', false);
        $this->assertSame($ataque, $respuesta->viewData('perfil')->datos_academicos);
        $this->assertSame('javascript:alert("WEB05-EVIDENCIA")', $respuesta->viewData('habilidadesPerfil')[0]->evidencia);
    }

    public function test_solo_existe_perfil_propio_sin_lectura_arbitraria_de_otro_alumno(): void
    {
        $this->entrar();
        $this->get('/perfil/-250003')->assertNotFound();
        $respuesta = $this->get('/perfil?usuario_id=-250003')->assertOk();
        $this->assertNull($respuesta->viewData('perfil'));
        $respuesta->assertDontSee('DATOS_ACADEMICOS_AJENOS_WEB05')->assertDontSee('WEB05-OTRO-001');
    }

    public static function rolesSinAcceso(): array
    {
        return ['administrador' => ['admin'], 'empresa' => ['empresa']];
    }

    #[DataProvider('rolesSinAcceso')]
    public function test_otros_roles_no_acceden_al_perfil_ni_al_catalogo(string $rol): void
    {
        $this->entrar($rol);
        $this->get('/perfil')->assertForbidden();
        $this->put('/perfil', ['version' => str_repeat('a', 64), 'matricula' => 'NO'])->assertForbidden();
        $this->get('/catalogo')->assertForbidden();
        $this->get('/catalogo/-250201')->assertForbidden();
    }

    public function test_invitados_no_acceden_a_perfiles_ni_catalogo(): void
    {
        foreach (['/perfil', '/catalogo', '/catalogo/-250201'] as $ruta) {
            $this->get($ruta)->assertRedirect('/login');
        }
        $this->put('/perfil', ['matricula' => 'NO'])->assertRedirect('/login');
    }

    public static function cuentasInactivas(): array
    {
        return ['alumno sin perfil' => ['web02-inactivo@example.invalid'], 'profesor con perfil' => ['web05-inactivo-profesor@example.invalid']];
    }

    #[DataProvider('cuentasInactivas')]
    public function test_cuenta_inactiva_no_puede_iniciar_sesion_para_usar_web05(string $correo): void
    {
        $this->post('/login', ['correo' => $correo, 'password' => self::PASSWORD])
            ->assertRedirect()->assertSessionHasErrors('correo');
        $this->get('/perfil')->assertRedirect('/login');
        $this->get('/catalogo')->assertRedirect('/login');
    }

    public function test_clave_temporal_debe_actualizarse_antes_de_perfiles_y_catalogo(): void
    {
        $this->post('/login', ['correo' => 'web02-temporal@example.invalid', 'password' => self::PASSWORD])->assertRedirect('/clave');
        $this->get('/perfil')->assertRedirect('/clave');
        $this->get('/catalogo')->assertRedirect('/clave');
    }

    public function test_csrf_real_impide_escribir_y_permite_formulario_con_token(): void
    {
        $this->entrar();
        $datos = $this->datosAlumno();
        $this->app->bind(PreventRequestForgery::class, CsrfActivoEnPerfiles::class);
        $this->put('/perfil', $datos)->assertStatus(419);
        $this->assertNull($this->perfil()->perfil);
        $this->put('/perfil', array_replace($datos, ['_token' => session()->token()]))
            ->assertRedirect('/perfil')->assertSessionHasNoErrors();
        $this->assertSame('WEB05-PROPIO-001', $this->perfil()->perfil->matricula);
    }

    public function test_catalogo_paginado_es_estable_y_no_repite_filas(): void
    {
        $this->entrar();
        $primera = $this->listado();
        $segunda = $this->listado('?page=2');
        $this->assertSame(25, $primera->total());
        $this->assertSame(20, $primera->count());
        $this->assertSame(5, $segunda->count());
        $this->assertSame([], array_values(array_intersect($this->ids($primera), $this->ids($segunda))));
        $this->assertSame($this->ids($primera), $this->ids($this->listado()));
    }

    public static function filtrosCatalogo(): array
    {
        return [
            'búsqueda' => ['buscar=Inventario', [-250201]],
            'empresa y modalidad' => ['empresa_id=-220102&modalidad=presencial', [-250202]],
            'habilidad dura' => ['habilidad_id=-250101&tipo_habilidad=dura', [-250201]],
            'habilidad blanda' => ['tipo_habilidad=blanda', [-250202]],
            'intersección vacía' => ['empresa_id=-220102&habilidad_id=-250101', []],
            'sin coincidencia' => ['buscar=INEXISTENTE_WEB05', []],
            'sql como texto' => ['buscar=%27%20OR%201%3D1%20--', []],
        ];
    }

    #[DataProvider('filtrosCatalogo')]
    public function test_catalogo_aplica_filtros_combinados_sin_ampliar_resultados(string $filtros, array $ids): void
    {
        $this->entrar();
        $this->assertSame($ids, $this->ids($this->listado('?'.$filtros)));
    }

    public function test_coincidencia_de_habilidades_usa_perfil_propio_e_instantanea_publicada(): void
    {
        $this->entrar();
        $respuesta = $this->get('/catalogo?buscar=Inventario')->assertOk();
        $coincidencia = $respuesta->viewData('coincidencias')[-250201];
        $this->assertSame([1, 0, 1], [$coincidencia->requeridas, $coincidencia->cumplidas, $coincidencia->faltan_obligatorias]);
        // Nombre de la instantánea aprobada, no el renombrado posterior.
        $this->assertSame('Programación WEB05', $coincidencia->faltantes[0]->nombre);
        $respuesta->assertSee('Cumples 0 de 1')->assertDontSee('NOMBRE_NUEVO_NO_APROBADO_WEB05');

        $this->put('/perfil', $this->datosAlumno(['habilidades_seleccionadas' => [-250101]]))->assertRedirect('/perfil');
        $detalle = $this->get('/catalogo/-250201')->assertOk()->assertSee('Cumples 1 de 1');
        $this->assertSame([1, 1, []], [$detalle->viewData('coincidencia')->requeridas,
            $detalle->viewData('coincidencia')->cumplidas, $detalle->viewData('coincidencia')->faltantes]);
    }

    public function test_profesor_no_recibe_coincidencia_de_habilidades_de_alumno(): void
    {
        $this->entrar('profesor');
        $this->assertSame([], $this->get('/catalogo?buscar=Inventario')->assertOk()->viewData('coincidencias'));
        $this->assertNull($this->get('/catalogo/-250201')->assertOk()->viewData('coincidencia'));
    }

    public function test_avance_del_perfil_indica_datos_faltantes_sin_bloquear(): void
    {
        $this->entrar();
        $this->put('/perfil', $this->datosAlumno(['carrera' => '', 'contacto_telefono' => '']))->assertRedirect('/perfil');
        $avance = $this->get('/perfil')->assertOk()->assertSee('Perfil completo al 57 %')->viewData('avance');
        $this->assertSame(['campo-carrera', 'campo-contacto_telefono', 'habilidades-ayuda'], array_column($avance->faltantes, 'campo'));
        $this->put('/perfil', $this->datosAlumno(['habilidades_seleccionadas' => [-250101]]))->assertRedirect('/perfil');
        $this->get('/panel')->assertOk()->assertSee('Perfil completo al 100 %');
    }

    public function test_profesor_consulta_publicaciones_y_disponibilidad_de_direccion(): void
    {
        $this->entrar('profesor');
        $this->assertSame([-250201], $this->ids($this->listado('?buscar=Inventario')));
        $proyecto = $this->get('/catalogo/-250201')->assertOk()->viewData('proyecto');
        $this->assertFalse($proyecto->disponibilidad->direccion_disponible);
        $this->assertSame(3, $proyecto->disponibilidad->plazas_disponibles);
    }

    public function test_publicado_con_cupo_agotado_sigue_visible_con_disponibilidad_cero(): void
    {
        $this->entrar();
        $this->assertSame([-250207], $this->ids($this->listado('?buscar=Cupo%20agotado')));
        $proyecto = $this->get('/catalogo/-250207')->assertOk()->viewData('proyecto');
        $this->assertSame(0, $proyecto->disponibilidad->plazas_disponibles);
        $this->assertTrue($proyecto->disponibilidad->direccion_disponible);
    }

    public static function proyectosNoPublicos(): array
    {
        return ['borrador' => [-250203], 'corrección' => [-250204], 'rechazado' => [-250205],
            'revisión antigua sin aprobar' => [-240201], 'publicado v1 sin cupo validado' => [-250206], 'inexistente' => [-999999999]];
    }

    #[DataProvider('proyectosNoPublicos')]
    public function test_detalle_oculta_proyectos_no_publicados_o_sin_cupo_validado(int $id): void
    {
        $this->entrar();
        $this->get('/catalogo/'.$id)->assertNotFound();
        $this->assertNotContains($id, $this->ids($this->listado()));
    }

    public function test_catalogo_usa_instantanea_aprobada_y_solo_datos_publicos(): void
    {
        $this->entrar();
        $respuesta = $this->get('/catalogo/-250201')->assertOk();
        $proyecto = $respuesta->viewData('proyecto');
        $this->assertSame('Inventario WEB05', $proyecto->titulo);
        $this->assertSame('Descripción publicada WEB05', $proyecto->descripcion);
        $this->assertSame('Programación WEB05', $proyecto->habilidades[0]->nombre);
        $this->assertSame('Intermedio aprobado WEB05', $proyecto->habilidades[0]->nivel_minimo);
        $this->assertSame('empresa-contacto-web05@example.invalid', $proyecto->empresa->contacto_correo);
        $dto = json_encode($proyecto, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
        foreach (['MOTIVO_PRIVADO_WEB05', 'hash_contrasena', 'correo_normalizado', 'autor_usuario_id',
            'administrador_usuario_id', 'web02-empresa@example.invalid', 'DATOS_ACADEMICOS_AJENOS_WEB05',
            'NOMBRE_NUEVO_NO_APROBADO_WEB05'] as $privado) {
            $this->assertStringNotContainsString($privado, $dto);
            $respuesta->assertDontSee($privado);
        }
        $this->get('/catalogo?buscar=Inventario')->assertOk()->assertDontSee('MOTIVO_PRIVADO_WEB05')
            ->assertDontSee('web02-empresa@example.invalid')->assertDontSee('hash_contrasena');
    }

    public function test_opciones_del_catalogo_no_delatan_empresa_historica_sin_publicaciones_validas(): void
    {
        $this->entrar();
        $opciones = $this->get('/catalogo')->assertOk()->viewData('opciones');
        $serializado = json_encode($opciones, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
        $this->assertStringNotContainsString('Empresa histórica WEB05', $serializado);
        $this->assertStringNotContainsString('PUBLICADO_LEGADO_SIN_CUPO_WEB05', $serializado);
        $this->assertStringContainsString('Programación WEB05', $serializado);
        $this->assertStringNotContainsString('NOMBRE_NUEVO_NO_APROBADO_WEB05', $serializado);
    }

    public static function filtrosInvalidos(): array
    {
        return ['arreglo' => ['buscar%5B%5D=x', 'buscar'], 'tipo' => ['tipo_habilidad=secreta', 'tipo_habilidad'],
            'página cero' => ['page=0', 'page'], 'empresa no entera' => ['empresa_id=1.5', 'empresa_id'],
            'habilidad no entera' => ['habilidad_id=texto', 'habilidad_id']];
    }

    #[DataProvider('filtrosInvalidos')]
    public function test_filtros_malformados_no_producen_errores_internos(string $filtro, string $campo): void
    {
        $this->entrar();
        $this->get('/catalogo?'.$filtro)->assertRedirect()->assertSessionHasErrors($campo);
    }
}
