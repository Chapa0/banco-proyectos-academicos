<?php

namespace Tests\Unit;

use App\Models\Usuario;
use PHPUnit\Framework\TestCase;

class UsuarioTest extends TestCase
{
    public function test_el_mapeo_no_asume_las_columnas_predeterminadas_de_laravel(): void
    {
        $usuario = new Usuario;
        $usuario->forceFill(['id' => 1, 'nombre' => 'Ejemplo', 'hash_contrasena' => 'secreto']);

        $this->assertSame('banco.usuario', $usuario->getTable());
        $this->assertSame('id', $usuario->getKeyName());
        $this->assertSame('hash_contrasena', $usuario->getAuthPasswordName());
        $this->assertFalse($usuario->usesTimestamps());
        $this->assertArrayNotHasKey('hash_contrasena', $usuario->toArray());
    }
}
