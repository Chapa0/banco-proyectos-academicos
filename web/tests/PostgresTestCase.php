<?php

namespace Tests;

use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use RuntimeException;

abstract class PostgresTestCase extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        $database = getenv('BANCO_TEST_DATABASE');
        if (! $database || ! getenv('BANCO_TEST_WEB02')) {
            $this->markTestSkipped('Ejecuta python tests/acceso.py para preparar la integración WEB-02.');
        }
        if (! preg_match('/\Abanco_proyectos_test_[0-9a-f]{12}\z/', $database)) {
            throw new RuntimeException('Las pruebas de acceso requieren una base temporal propia.');
        }
        $host = getenv('BANCO_TEST_HOST');
        $port = getenv('BANCO_TEST_PORT');
        $username = getenv('BANCO_TEST_USERNAME');
        $password = getenv('BANCO_TEST_PASSWORD');
        if (! in_array($host, ['127.0.0.1', 'localhost', '::1'], true)
            || ! $port || ! ctype_digit($port) || (int) $port < 1 || (int) $port > 65535
            || ! $username || $username === 'proweb_admin' || ! $password) {
            throw new RuntimeException('Falta la configuración protegida de PostgreSQL.');
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
        DB::connection('pgsql')->beginTransaction();
        Cache::flush();
    }

    public function call($method, $uri, $parameters = [], $cookies = [], $files = [], $server = [], $content = null)
    {
        // Cada petición real obtiene el usuario de nuevo. El contenedor de los
        // tests persiste entre peticiones; no conservar un guard en memoria.
        Auth::forgetGuards();

        return parent::call($method, $uri, $parameters, $cookies, $files, $server, $content);
    }

    protected function tearDown(): void
    {
        if ($this->app !== null) {
            $connection = DB::connection('pgsql');
            while ($connection->transactionLevel() > 0) {
                $connection->rollBack();
            }
            DB::purge('pgsql');
        }

        parent::tearDown();
    }
}
