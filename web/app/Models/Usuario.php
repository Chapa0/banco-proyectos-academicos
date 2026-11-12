<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;

class Usuario extends Authenticatable
{
    protected $table = 'banco.usuario';

    public $timestamps = false;

    protected $guarded = ['*'];

    protected $hidden = ['hash_contrasena'];

    protected $rememberTokenName = '';

    public function getAuthPasswordName(): string
    {
        return 'hash_contrasena';
    }

    protected function casts(): array
    {
        return ['fecha_alta' => 'immutable_datetime', 'version_acceso' => 'integer', 'requiere_cambio_clave' => 'boolean'];
    }
}
