<?php

namespace Tests\Integration;

use App\Models\Usuario;
use App\Services\ConexionPostgres;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use PDO;
use PHPUnit\Framework\Attributes\DataProvider;
use RuntimeException;
use Tests\TestCase;

class PostgresConnectionTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        $database = getenv('BANCO_TEST_DATABASE');
        if ($database === false || $database === '') {
            $this->markTestSkipped('Ejecuta python tests/postgres.py para preparar una base temporal propia.');
        }
        if (! preg_match('/\Abanco_proyectos_test_[0-9a-f]{12}\z/', $database)) {
            throw new RuntimeException('La integración solo admite una base temporal del ejecutor.');
        }

        $host = getenv('BANCO_TEST_HOST');
        $port = getenv('BANCO_TEST_PORT');
        $username = getenv('BANCO_TEST_USERNAME');
        $password = getenv('BANCO_TEST_PASSWORD');
        if (! in_array($host, ['127.0.0.1', 'localhost', '::1'], true)
            || $port === false || ! ctype_digit($port) || (int) $port < 1 || (int) $port > 65535
            || $username === false || $username === '' || $username === 'proweb_admin'
            || $password === false || $password === '') {
            throw new RuntimeException('Falta la configuración local privada de la integración.');
        }

        config(['database.default' => 'pgsql']);
        config(['database.connections.pgsql' => array_replace(config('database.connections.pgsql'), [
            'url' => null,
            'host' => $host,
            'port' => $port,
            'database' => $database,
            'username' => $username,
            'password' => $password,
            'search_path' => 'banco',
            'timezone' => 'UTC',
            'isolation_level' => 'READ COMMITTED',
        ])]);
        DB::purge('pgsql');
    }

    protected function tearDown(): void
    {
        if ($this->app !== null) {
            DB::purge('pgsql');
        }

        parent::tearDown();
    }

    public function test_real_connection_uses_the_isolated_database_and_application_role(): void
    {
        $estado = app(ConexionPostgres::class)->comprobar();

        $this->assertSame(getenv('BANCO_TEST_DATABASE'), $estado['base']);
        $this->assertSame(getenv('BANCO_TEST_USERNAME'), $estado['usuario']);
        $this->assertSame('banco', $estado['esquema']);
        $this->assertSame('UTC', $estado['zona_horaria']);
        $this->assertSame('read committed', $estado['aislamiento']);
        $this->assertFalse($estado['privilegiada']);
        $this->assertFalse($estado['puede_crear']);
        $this->assertFalse($estado['puede_leer_cuentas']);
        $this->assertSame('pgsql', DB::connection('pgsql')->getPdo()->getAttribute(PDO::ATTR_DRIVER_NAME));
    }

    public function test_directory_query_only_returns_the_five_permitted_columns(): void
    {
        // El ejecutor prepara exclusivamente datos ficticios en la temporal.
        $fila = DB::table('banco.v_usuario_directorio')->orderBy('id')->first();

        $this->assertNotNull($fila);
        $this->assertSame(['id', 'nombre', 'rol_principal', 'estado_cuenta', 'fecha_alta'], array_keys((array) $fila));
        $this->assertArrayNotHasKey('hash_contrasena', (array) $fila);
        $this->assertArrayNotHasKey('correo_normalizado', (array) $fila);
    }

    public function test_user_mapping_keeps_the_existing_schema_and_password_column(): void
    {
        $usuario = new Usuario;

        $this->assertSame('banco.usuario', $usuario->getTable());
        $this->assertSame('hash_contrasena', $usuario->getAuthPasswordName());
        $this->assertFalse($usuario->usesTimestamps());
        $this->assertContains('hash_contrasena', $usuario->getHidden());
    }

    #[DataProvider('operacionesRestringidas')]
    public function test_application_credential_cannot_access_restricted_objects(string $sql): void
    {
        try {
            DB::connection('pgsql')->statement($sql);
            $this->fail('La credencial de WEB-01 aceptó una operación restringida.');
        } catch (QueryException $error) {
            $this->assertSame('42501', $error->errorInfo[0] ?? null);
        }
    }

    public static function operacionesRestringidas(): array
    {
        return [
            'hashes' => ['SELECT hash_contrasena FROM banco.usuario LIMIT 0'],
            'cuentas completas' => ['SELECT * FROM banco.usuario LIMIT 0'],
            'proyectos' => ['SELECT * FROM banco.proyecto LIMIT 0'],
            'auditoría' => ['SELECT * FROM banco.evento_auditoria LIMIT 0'],
            'escritura' => ["UPDATE banco.proyecto SET titulo='No permitido' WHERE false"],
            'DDL de negocio' => ['CREATE TABLE banco.prueba_permiso_web(id integer)'],
            'secuencia' => ["SELECT nextval('banco.usuario_id_seq')"],
            'función de negocio' => ['SELECT banco.consultar_perfil(0,0)'],
        ];
    }

    public function test_connection_command_returns_valid_json_without_the_password(): void
    {
        $resultado = Artisan::call('banco:comprobar-conexion', ['--json' => true]);
        $salida = Artisan::output();
        $estado = json_decode($salida, true, 512, JSON_THROW_ON_ERROR);

        $this->assertSame(0, $resultado);
        $this->assertSame(getenv('BANCO_TEST_DATABASE'), $estado['base']);
        $this->assertSame(getenv('BANCO_TEST_USERNAME'), $estado['usuario']);
        $this->assertFalse($estado['privilegiada']);
        $this->assertStringNotContainsString(getenv('BANCO_TEST_PASSWORD'), $salida);
    }

    public function test_connection_failure_is_reported_without_private_details(): void
    {
        $original = config('database.connections.pgsql');
        try {
            // Puerto local reservado para provocar un rechazo de conexión real.
            config(['database.connections.pgsql.port' => '1']);
            DB::purge('pgsql');

            $resultado = Artisan::call('banco:comprobar-conexion', ['--json' => true]);
            $salida = Artisan::output();

            $this->assertSame(1, $resultado);
            $this->assertStringContainsString('No fue posible verificar PostgreSQL.', $salida);
            foreach ([getenv('BANCO_TEST_PASSWORD'), getenv('BANCO_TEST_DATABASE'), getenv('BANCO_TEST_USERNAME'), 'SQLSTATE', 'PDOException'] as $detalle) {
                $this->assertStringNotContainsString($detalle, $salida);
            }
        } finally {
            config(['database.connections.pgsql' => $original]);
            DB::purge('pgsql');
        }
    }
}
