<?php

namespace App\Console\Commands;

use App\Services\ConexionPostgres;
use Illuminate\Console\Command;
use Throwable;

class ComprobarConexion extends Command
{
    protected $signature = 'banco:comprobar-conexion {--json : Resultado estructurado sin secretos}';

    protected $description = 'Comprueba PostgreSQL, esquema y permisos mínimos de la conexión web';

    public function handle(ConexionPostgres $conexion): int
    {
        try {
            $estado = $conexion->comprobar();
        } catch (Throwable) {
            $this->error('No fue posible verificar PostgreSQL. Revisa el servidor y la configuración privada de la conexión.');

            return self::FAILURE;
        }

        if ($this->option('json')) {
            $this->line(json_encode($estado, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE));
        } else {
            $this->info('Conexión PostgreSQL correcta, esquema banco y permisos mínimos verificados.');
        }

        return self::SUCCESS;
    }
}
