<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use RuntimeException;

class ConexionPostgres
{
    /** @return array<string, mixed> */
    public function comprobar(): array
    {
        $db = DB::connection('pgsql');
        $estado = $db->selectOne(<<<'SQL'
            SELECT current_database() AS base, current_user AS usuario,
                current_schema() AS esquema,
                current_setting('server_version') AS postgres,
                current_setting('TimeZone') AS zona_horaria,
                current_setting('transaction_isolation') AS aislamiento,
                r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolreplication
                    OR r.rolbypassrls AS privilegiada,
                has_schema_privilege(current_user,'banco','CREATE') AS puede_crear,
                has_table_privilege(current_user,'banco.usuario','SELECT') AS puede_leer_cuentas
            FROM pg_roles r WHERE r.rolname=current_user
            SQL);

        if ($estado->esquema !== 'banco' || $estado->zona_horaria !== 'UTC'
            || $estado->aislamiento !== 'read committed' || $estado->privilegiada
            || $estado->puede_crear || $estado->puede_leer_cuentas) {
            throw new RuntimeException('La conexión no cumple la configuración y permisos de WEB-01.');
        }

        // Comprueba las columnas permitidas sin obtener datos personales.
        $db->select('SELECT id,nombre,rol_principal,estado_cuenta,fecha_alta FROM banco.v_usuario_directorio LIMIT 0');

        return (array) $estado;
    }
}
