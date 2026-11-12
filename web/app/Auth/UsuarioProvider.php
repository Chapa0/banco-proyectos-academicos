<?php

namespace App\Auth;

use App\Models\Usuario;
use Illuminate\Contracts\Auth\Authenticatable;
use Illuminate\Contracts\Auth\UserProvider;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class UsuarioProvider implements UserProvider
{
    public function retrieveById($identifier): ?Usuario
    {
        if (! preg_match('/^-?\d+$/', (string) $identifier)) {
            return null;
        }

        return $this->usuario(DB::selectOne('SELECT * FROM banco.web_buscar_acceso_id(?)', [$identifier]));
    }

    public function retrieveByToken($identifier, #[\SensitiveParameter] $token): ?Usuario
    {
        return null;
    }

    public function updateRememberToken(Authenticatable $user, #[\SensitiveParameter] $token): void {}

    public function retrieveByCredentials(#[\SensitiveParameter] array $credentials): ?Usuario
    {
        $correo = $credentials['correo_normalizado'] ?? $credentials['correo'] ?? null;
        if (! is_string($correo) || $correo === '') {
            return null;
        }

        return $this->usuario(DB::selectOne('SELECT * FROM banco.web_buscar_acceso_correo(?)', [$correo]));
    }

    public function validateCredentials(Authenticatable $user, #[\SensitiveParameter] array $credentials): bool
    {
        $hash = $user->getAuthPassword();
        if (! is_string($hash) || password_get_info($hash)['algoName'] !== 'bcrypt') {
            return false;
        }

        return Hash::check($credentials['password'] ?? '', $hash) && $user->estado_cuenta === 'activa';
    }

    public function rehashPasswordIfRequired(Authenticatable $user, #[\SensitiveParameter] array $credentials, bool $force = false): void
    {
        // Los hashes se renuevan por el servicio auditado de cambio de clave.
        // El proveedor no escribe directamente en la tabla de cuentas.
    }

    private function usuario(?object $fila): ?Usuario
    {
        return $fila === null ? null : (new Usuario)->newFromBuilder((array) $fila);
    }
}
