<?php

namespace Tests\Integration;

use Illuminate\Foundation\Http\Middleware\PreventRequestForgery;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\PostgresTestCase;

class CsrfActivoEnPruebas extends PreventRequestForgery
{
    protected function runningUnitTests()
    {
        return false;
    }
}

class AccesoCuentasTest extends PostgresTestCase
{
    private const ADMIN = -220001;

    private const OTRO_ADMIN = -220002;

    private const ALUMNO = -220003;

    private const PROFESOR = -220004;

    private const REPRESENTANTE = -220005;

    private const INACTIVO = -220007;

    private const TEMPORAL = -220008;

    private const PASSWORD = 'PruebaSegura-2026!';

    private const PASSWORD_NUEVO = 'CambioSeguro-2026!';

    private function entrar(string $correo = 'web02-admin@example.invalid', string $password = self::PASSWORD)
    {
        return $this->post('/login', ['correo' => $correo, 'password' => $password]);
    }

    private function acceso(int $id): object
    {
        return DB::selectOne('SELECT * FROM banco.web_buscar_acceso_id(?)', [$id]);
    }

    private function cuenta(int $id): array
    {
        return json_decode(DB::selectOne('SELECT banco.web_obtener_cuenta(?,?) AS cuenta', [self::ADMIN, $id])->cuenta, true, 512, JSON_THROW_ON_ERROR);
    }

    private function buscar(string $correo): ?array
    {
        $resultado = json_decode(DB::selectOne('SELECT banco.web_listar_cuentas(?,?,?,?,?,?) AS cuentas',
            [self::ADMIN, $correo, '', '', 20, 0])->cuentas, true, 512, JSON_THROW_ON_ERROR);

        return collect($resultado['datos'])->first(fn (array $cuenta) => $cuenta['correo_normalizado'] === $correo);
    }

    private function alta(string $rol, array $extra = []): array
    {
        return array_replace([
            'nombre' => 'Cuenta nueva de prueba',
            'correo' => 'nueva-'.$rol.'@example.invalid',
            'rol' => $rol,
            'razon_social' => $rol === 'empresa' ? 'Empresa nueva de prueba' : '',
            'password' => self::PASSWORD_NUEVO,
            'password_confirmation' => self::PASSWORD_NUEVO,
        ], $extra);
    }

    #[DataProvider('rolesConAcceso')]
    public function test_cada_rol_activo_inicia_sesion_y_consulta_su_panel(string $correo, int $id, bool $admin): void
    {
        $this->entrar($correo)->assertRedirect('/panel');
        $this->assertAuthenticated();
        $this->assertSame($id, (int) Auth::id());
        $panel = $this->get('/panel')->assertOk()->assertSee($correo)->assertDontSee('hash_contrasena');
        if ($admin) {
            $panel->assertSee('/admin/cuentas', false);
        } else {
            $panel->assertDontSee('/admin/cuentas', false);
        }
    }

    public static function rolesConAcceso(): array
    {
        return [
            'administrador' => ['web02-admin@example.invalid', self::ADMIN, true],
            'alumno' => ['web02-alumno@example.invalid', self::ALUMNO, false],
            'profesor' => ['web02-profesor@example.invalid', self::PROFESOR, false],
            'empresa' => ['web02-empresa@example.invalid', self::REPRESENTANTE, false],
        ];
    }

    public function test_correo_normalizado_y_regeneracion_de_sesion_al_entrar(): void
    {
        $this->get('/login')->assertOk();
        $anterior = session()->getId();
        $this->entrar(' WEB02-ADMIN@EXAMPLE.INVALID ')->assertRedirect('/panel');

        $this->assertNotSame($anterior, session()->getId());
        $this->assertSame(self::ADMIN, (int) Auth::id());
        $this->assertSame((int) $this->acceso(self::ADMIN)->version_acceso, (int) session('acceso_version'));
    }

    public function test_correo_en_array_devuelve_validacion_y_permite_reabrir_el_login(): void
    {
        $this->from('/login')->post('/login', [
            'correo' => ['entrada' => 'correo-no-escalar@example.invalid'],
            'password' => self::PASSWORD,
        ])->assertRedirect('/login')->assertSessionHasErrors('correo');

        $this->assertGuest();
        $this->withCookie(config('session.cookie'), session()->getId());
        $this->get('/login')->assertOk()->assertSee('correo-error', false)
            ->assertDontSee('correo-no-escalar@example.invalid')
            ->assertDontSee(self::PASSWORD, false);
    }

    public function test_fallos_no_revelan_si_la_cuenta_existe_o_esta_inactiva(): void
    {
        $mensajes = [];
        foreach ([
            ['desconocido@example.invalid', self::PASSWORD],
            ['web02-alumno@example.invalid', 'Incorrecta-2026!'],
            ['web02-inactivo@example.invalid', self::PASSWORD],
            ['web02-demo@example.invalid', self::PASSWORD],
        ] as [$correo, $password]) {
            $this->entrar($correo, $password)->assertSessionHasErrors('correo');
            $mensajes[] = session('errors')->getBag('default')->get('correo');
            $this->assertGuest();
            $this->assertArrayNotHasKey('password', session('_old_input', []));
        }
        foreach ($mensajes as $mensaje) {
            $this->assertSame($mensajes[0], $mensaje);
        }
    }

    public function test_cierre_solo_por_post_invalida_sesion_y_token(): void
    {
        $this->entrar()->assertRedirect('/panel');
        $id = session()->getId();
        $token = session()->token();
        $this->get('/logout')->assertStatus(405);
        $this->post('/logout')->assertRedirect();
        $this->assertGuest();
        $this->assertNotSame($id, session()->getId());
        $this->assertNotSame($token, session()->token());
        $this->get('/panel')->assertRedirect('/login');
    }

    public function test_sin_sesion_no_hay_panel_ni_administracion_ni_autorregistro(): void
    {
        $this->get('/panel')->assertRedirect('/login');
        $this->get('/admin/cuentas')->assertRedirect('/login');
        $this->get('/register')->assertNotFound();
        $this->post('/register', $this->alta('administrador'))->assertNotFound();
        $this->get('/forgot-password')->assertNotFound();
    }

    #[DataProvider('actoresNoAdministrativos')]
    public function test_otro_rol_no_puede_administrar_por_peticion_directa_o_actor_falsificado(string $correo): void
    {
        $this->entrar($correo)->assertRedirect('/panel');
        $this->get('/admin/cuentas')->assertForbidden();
        $this->get('/admin/cuentas/crear')->assertForbidden();
        $this->get('/admin/cuentas/'.self::ADMIN.'/editar')->assertForbidden();
        $this->post('/admin/cuentas', $this->alta('administrador', ['admin_id' => self::ADMIN]))->assertForbidden();
        $this->post('/admin/cuentas/'.self::ADMIN.'/estado', [
            'estado' => 'inactiva', 'motivo' => 'Petición manipulada', 'version_acceso' => 1, 'admin_id' => self::ADMIN,
        ])->assertForbidden();
    }

    public static function actoresNoAdministrativos(): array
    {
        return [
            ['web02-alumno@example.invalid'],
            ['web02-profesor@example.invalid'],
            ['web02-empresa@example.invalid'],
        ];
    }

    public function test_csrf_real_rechaza_login_sin_token_y_lo_acepta_con_token(): void
    {
        $this->app->bind(PreventRequestForgery::class, CsrfActivoEnPruebas::class);
        $this->get('/login')->assertOk();
        $this->entrar()->assertStatus(419);
        $this->assertGuest();
        $this->post('/login', ['correo' => 'web02-admin@example.invalid', 'password' => self::PASSWORD,
            '_token' => session()->token()])->assertRedirect('/panel');
        $this->assertAuthenticated();
        $this->post('/logout')->assertStatus(419);
        $this->get('/panel')->assertOk();
        $this->post('/logout', ['_token' => session()->token()])->assertRedirect();
        $this->assertGuest();
    }

    public function test_csrf_real_protege_mutaciones_administrativas(): void
    {
        $this->entrar()->assertRedirect('/panel');
        $this->app->bind(PreventRequestForgery::class, CsrfActivoEnPruebas::class);
        $this->post('/admin/cuentas', $this->alta('alumno'))->assertStatus(419);
        $this->assertNull($this->buscar('nueva-alumno@example.invalid'));
    }

    public function test_sexto_intento_fallido_se_limita_sin_autenticar(): void
    {
        for ($i = 0; $i < 5; $i++) {
            $this->entrar('web02-alumno@example.invalid', 'Incorrecta-2026!')->assertSessionHasErrors('correo');
        }
        $this->entrar('web02-alumno@example.invalid', self::PASSWORD)->assertStatus(429);
        $this->assertGuest();
    }

    public function test_limite_por_ip_tambien_aplica_a_correos_distintos(): void
    {
        for ($i = 0; $i < 20; $i++) {
            $this->entrar('desconocido-'.$i.'@example.invalid', self::PASSWORD)->assertSessionHasErrors('correo');
        }
        $this->entrar('web02-admin@example.invalid')->assertStatus(429);
        $this->assertGuest();
    }

    public function test_clave_temporal_exige_cambio_antes_de_panel_o_administracion(): void
    {
        $this->entrar('web02-temporal@example.invalid')->assertRedirect('/clave');
        $this->get('/panel')->assertRedirect('/clave');
        $this->get('/admin/cuentas')->assertRedirect('/clave');
        $this->get('/clave')->assertOk();
        $anterior = $this->acceso(self::TEMPORAL);
        $this->put('/clave', ['current_password' => self::PASSWORD,
            'password' => self::PASSWORD_NUEVO, 'password_confirmation' => self::PASSWORD_NUEVO])->assertRedirect('/panel');
        $nuevo = $this->acceso(self::TEMPORAL);
        $this->assertFalse($nuevo->requiere_cambio_clave);
        $this->assertGreaterThan((int) $anterior->version_acceso, (int) $nuevo->version_acceso);
        $this->assertTrue(Hash::check(self::PASSWORD_NUEVO, $nuevo->hash_contrasena));
        $this->get('/panel')->assertOk();
        $this->post('/logout');
        $this->entrar('web02-temporal@example.invalid', self::PASSWORD_NUEVO)->assertRedirect('/panel');
    }

    public function test_cambio_propio_no_acepta_clave_actual_incorrecta_o_confirmacion_distinta(): void
    {
        $this->entrar('web02-alumno@example.invalid');
        $antes = $this->acceso(self::ALUMNO);
        $this->put('/clave', ['current_password' => 'Incorrecta-2026!',
            'password' => self::PASSWORD_NUEVO, 'password_confirmation' => self::PASSWORD_NUEVO])->assertSessionHasErrors();
        $this->put('/clave', ['current_password' => self::PASSWORD,
            'password' => self::PASSWORD_NUEVO, 'password_confirmation' => 'NoCoincide-2026!'])->assertSessionHasErrors();
        $this->assertSame($antes->hash_contrasena, $this->acceso(self::ALUMNO)->hash_contrasena);
    }

    public function test_cambio_propio_con_clave_en_array_devuelve_validacion_y_conserva_la_sesion(): void
    {
        $this->entrar('web02-alumno@example.invalid')->assertRedirect('/panel');
        $anterior = $this->acceso(self::ALUMNO)->hash_contrasena;
        $this->put('/clave', [
            'current_password' => self::PASSWORD,
            'password' => ['entrada' => 'malformada'],
            'password_confirmation' => ['entrada' => 'malformada'],
        ])->assertStatus(302)->assertSessionHasErrors('password');

        $this->assertAuthenticated();
        $this->assertSame(self::ALUMNO, (int) Auth::id());
        $this->assertSame($anterior, $this->acceso(self::ALUMNO)->hash_contrasena);
    }

    public function test_desactivar_invalida_la_sesion_y_reactivar_no_la_resucita(): void
    {
        $this->entrar('web02-alumno@example.invalid');
        $this->get('/panel')->assertOk();
        DB::selectOne('SELECT banco.web_estado_cuenta(?,?,?,?,?)',
            [self::ADMIN, self::ALUMNO, 'inactiva', 'Baja de prueba', $this->acceso(self::ALUMNO)->version_acceso]);
        $this->get('/panel')->assertRedirect('/login');
        $this->assertGuest();
        DB::selectOne('SELECT banco.web_estado_cuenta(?,?,?,?,?)',
            [self::ADMIN, self::ALUMNO, 'activa', 'Reactivación de prueba', $this->acceso(self::ALUMNO)->version_acceso]);
        $this->get('/panel')->assertRedirect('/login');
    }

    public function test_restablacer_clave_desde_otro_admin_invalida_la_sesion_anterior(): void
    {
        $this->entrar('web02-alumno@example.invalid');
        DB::selectOne('SELECT banco.web_restablecer_clave(?,?,?,?,?)', [self::ADMIN, self::ALUMNO,
            Hash::make(self::PASSWORD_NUEVO), 'Restablecimiento de prueba', $this->acceso(self::ALUMNO)->version_acceso]);
        $this->get('/panel')->assertRedirect('/login');
        $this->assertGuest();
        $this->entrar('web02-alumno@example.invalid', self::PASSWORD_NUEVO)->assertRedirect('/clave');
    }

    #[DataProvider('rolesParaAlta')]
    public function test_admin_crea_cada_tipo_de_cuenta_con_clave_temporal_y_hash_oculto(string $rol): void
    {
        $this->entrar();
        $datos = $this->alta($rol, ['correo' => ' NUEVA-'.$rol.'@EXAMPLE.INVALID ', 'admin_id' => self::ALUMNO]);
        $this->post('/admin/cuentas', $datos)->assertRedirect();
        $cuenta = $this->buscar('nueva-'.$rol.'@example.invalid');
        $this->assertNotNull($cuenta);
        $this->assertSame($rol, $cuenta['rol_principal']);
        $this->assertTrue($cuenta['requiere_cambio_clave']);
        $this->assertArrayNotHasKey('hash_contrasena', $cuenta);
        $this->assertTrue(Hash::check(self::PASSWORD_NUEVO, $this->acceso((int) $cuenta['id'])->hash_contrasena));
        $this->get('/admin/cuentas')->assertOk()->assertDontSee(self::PASSWORD_NUEVO, false)->assertDontSee('hash_contrasena');
        if ($rol === 'empresa') {
            $this->assertNotNull($cuenta['empresa_id']);
            $this->assertSame('Empresa nueva de prueba', $cuenta['razon_social']);
        }
    }

    public static function rolesParaAlta(): array
    {
        return [['alumno'], ['profesor'], ['administrador'], ['empresa']];
    }

    public function test_admin_filtra_y_consulta_cuentas_sin_exponer_hash(): void
    {
        $this->entrar();
        $this->get('/admin/cuentas?buscar=web02-alumno%40example.invalid&rol=alumno&estado=activa')
            ->assertOk()->assertSee('web02-alumno@example.invalid')->assertDontSee('web02-profesor@example.invalid');
        $this->get('/admin/cuentas/'.self::ALUMNO.'/editar')->assertOk()
            ->assertSee('web02-alumno@example.invalid')->assertDontSee($this->acceso(self::ALUMNO)->hash_contrasena, false);
    }

    public function test_admin_edita_identidad_sin_convertir_el_rol_de_una_cuenta_existente(): void
    {
        $this->entrar();
        $this->put('/admin/cuentas/'.self::ALUMNO, [
            'nombre' => 'Alumno editado', 'correo' => 'ALUMNO.EDITADO@EXAMPLE.INVALID',
            'motivo' => 'Corrección de identidad de prueba', 'version_acceso' => $this->acceso(self::ALUMNO)->version_acceso,
            'rol' => 'administrador',
        ])->assertRedirect();
        $cuenta = $this->cuenta(self::ALUMNO);
        $this->assertSame('Alumno editado', $cuenta['nombre']);
        $this->assertSame('alumno.editado@example.invalid', $cuenta['correo_normalizado']);
        $this->assertSame('alumno', $cuenta['rol_principal']);
    }

    public function test_formulario_obsoleto_no_sobrescribe_una_cuenta_actualizada(): void
    {
        $this->entrar();
        $version = $this->acceso(self::ALUMNO)->version_acceso;
        $this->put('/admin/cuentas/'.self::ALUMNO, ['nombre' => 'Actualizado', 'correo' => 'actualizado@example.invalid',
            'motivo' => 'Primera actualización', 'version_acceso' => $version])->assertRedirect();
        $this->put('/admin/cuentas/'.self::ALUMNO, ['nombre' => 'Obsoleto', 'correo' => 'obsoleto@example.invalid',
            'motivo' => 'Formulario anterior', 'version_acceso' => $version])->assertSessionHasErrors();
        $this->assertSame('Actualizado', $this->cuenta(self::ALUMNO)['nombre']);
    }

    public function test_admin_desactiva_y_reactiva_sin_eliminar_ni_perder_la_identidad(): void
    {
        $this->entrar();
        $this->post('/admin/cuentas/'.self::ALUMNO.'/estado', ['estado' => 'inactiva', 'motivo' => 'Baja administrativa de prueba',
            'version_acceso' => $this->acceso(self::ALUMNO)->version_acceso])->assertRedirect();
        $this->assertSame('inactiva', $this->cuenta(self::ALUMNO)['estado_cuenta']);
        $this->post('/admin/cuentas/'.self::ALUMNO.'/estado', ['estado' => 'activa', 'motivo' => 'Reactivación administrativa de prueba',
            'version_acceso' => $this->acceso(self::ALUMNO)->version_acceso])->assertRedirect();
        $this->assertSame('activa', $this->cuenta(self::ALUMNO)['estado_cuenta']);
        $this->delete('/admin/cuentas/'.self::ALUMNO)->assertStatus(405);
    }

    public function test_se_conserva_al_ultimo_administrador_activo(): void
    {
        $this->entrar();
        $this->post('/admin/cuentas/'.self::OTRO_ADMIN.'/estado', ['estado' => 'inactiva', 'motivo' => 'Solo dejar un administrador',
            'version_acceso' => $this->acceso(self::OTRO_ADMIN)->version_acceso])->assertRedirect();
        $this->post('/admin/cuentas/'.self::ADMIN.'/estado', ['estado' => 'inactiva', 'motivo' => 'No debe quedar sin administrador',
            'version_acceso' => $this->acceso(self::ADMIN)->version_acceso])->assertSessionHasErrors();
        $this->assertSame('activa', $this->cuenta(self::ADMIN)['estado_cuenta']);
    }

    public function test_representante_vigente_no_se_desactiva_sin_relevo_y_el_relevo_conserva_empresa(): void
    {
        $this->entrar();
        $anterior = $this->cuenta(self::REPRESENTANTE);
        $this->post('/admin/cuentas/'.self::REPRESENTANTE.'/estado', ['estado' => 'inactiva', 'motivo' => 'Sin sustitución',
            'version_acceso' => $anterior['version_acceso']])->assertSessionHasErrors();
        $this->post('/admin/cuentas/'.self::REPRESENTANTE.'/relevo', [
            'nombre' => 'Representante nuevo', 'correo' => 'representante-nuevo@example.invalid',
            'password' => self::PASSWORD_NUEVO, 'password_confirmation' => self::PASSWORD_NUEVO,
            'motivo' => 'Relevo administrativo de prueba', 'empresa_id' => -220102,
        ])->assertRedirect();
        $nuevo = $this->buscar('representante-nuevo@example.invalid');
        $this->assertNotNull($nuevo);
        $this->assertSame((int) $anterior['empresa_id'], (int) $nuevo['empresa_id']);
        $this->assertSame('inactiva', $this->cuenta(self::REPRESENTANTE)['estado_cuenta']);
        $this->assertTrue($nuevo['requiere_cambio_clave']);
    }

    public function test_reset_administrativo_exige_motivo_y_marca_clave_temporal(): void
    {
        $this->entrar();
        $anterior = $this->acceso(self::ALUMNO);
        $datos = ['password' => self::PASSWORD_NUEVO, 'password_confirmation' => self::PASSWORD_NUEVO,
            'version_acceso' => $anterior->version_acceso];
        $this->post('/admin/cuentas/'.self::ALUMNO.'/clave', $datos)->assertSessionHasErrors('motivo');
        $this->post('/admin/cuentas/'.self::ALUMNO.'/clave', $datos + ['motivo' => 'Recuperación administrativa'])->assertRedirect();
        $actual = $this->acceso(self::ALUMNO);
        $this->assertTrue($actual->requiere_cambio_clave);
        $this->assertTrue(Hash::check(self::PASSWORD_NUEVO, $actual->hash_contrasena));
        $this->assertGreaterThan((int) $anterior->version_acceso, (int) $actual->version_acceso);
    }

    public function test_validacion_de_claves_y_correo_no_crea_cuentas_parciales(): void
    {
        $this->entrar();
        foreach ([
            ['password' => 'corta', 'password_confirmation' => 'corta'],
            ['password' => str_repeat('á', 40), 'password_confirmation' => str_repeat('á', 40)],
            ['password_confirmation' => 'No coincide'],
            ['rol' => 'superadmin'],
            ['correo' => 'web02-alumno@example.invalid'],
            ['rol' => 'empresa', 'razon_social' => ''],
        ] as $cambio) {
            $this->post('/admin/cuentas', $this->alta('alumno', $cambio))->assertSessionHasErrors();
        }
        $this->assertNull($this->buscar('nueva-alumno@example.invalid'));
    }

    public function test_nombres_se_escapan_en_las_vistas_y_no_se_muestra_la_clave_creada(): void
    {
        $this->entrar();
        $nombre = '<script>alert("prueba")</script>';
        $this->post('/admin/cuentas', $this->alta('alumno', ['nombre' => $nombre]))->assertRedirect();
        $this->get('/admin/cuentas')->assertOk()->assertSee($nombre)->assertDontSee($nombre, false)
            ->assertDontSee(self::PASSWORD_NUEVO, false);
    }
}
