<?php

namespace App\Providers;

use App\Auth\UsuarioProvider;
use App\Models\Usuario;
use Illuminate\Console\Events\CommandStarting;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;
use RuntimeException;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Auth::provider('banco', fn () => new UsuarioProvider);
        Gate::define('administrar-cuentas', fn (Usuario $usuario) => $usuario->rol_principal === 'administrador'
            && $usuario->estado_cuenta === 'activa' && ! $usuario->requiere_cambio_clave);
        Gate::define('gestionar-proyectos', fn (Usuario $usuario) => $usuario->rol_principal === 'empresa'
            && $usuario->estado_cuenta === 'activa' && ! $usuario->requiere_cambio_clave);
        Gate::define('revisar-proyectos', fn (Usuario $usuario) => $usuario->rol_principal === 'administrador'
            && $usuario->estado_cuenta === 'activa' && ! $usuario->requiere_cambio_clave);
        Gate::define('gestionar-perfil', fn (Usuario $usuario) => in_array($usuario->rol_principal, ['alumno', 'profesor'], true)
            && $usuario->estado_cuenta === 'activa' && ! $usuario->requiere_cambio_clave);
        Gate::define('consultar-catalogo', fn (Usuario $usuario) => in_array($usuario->rol_principal, ['alumno', 'profesor'], true)
            && $usuario->estado_cuenta === 'activa' && ! $usuario->requiere_cambio_clave);
        Gate::define('participar', fn (Usuario $usuario) => in_array($usuario->rol_principal, ['alumno', 'profesor'], true)
            && $usuario->estado_cuenta === 'activa' && ! $usuario->requiere_cambio_clave);
        Gate::define('consultar-participacion', fn (Usuario $usuario) => in_array($usuario->rol_principal, ['alumno', 'profesor', 'empresa', 'administrador'], true)
            && $usuario->estado_cuenta === 'activa' && ! $usuario->requiere_cambio_clave);
        Gate::define('gestionar-ciclo', fn (Usuario $usuario) => $usuario->rol_principal === 'administrador'
            && $usuario->estado_cuenta === 'activa' && ! $usuario->requiere_cambio_clave);
        Gate::define('consultar-avisos', fn (Usuario $usuario) => in_array($usuario->rol_principal, ['alumno', 'profesor', 'empresa', 'administrador'], true)
            && $usuario->estado_cuenta === 'activa' && ! $usuario->requiere_cambio_clave);
        Gate::define('consultar-reportes', fn (Usuario $usuario) => $usuario->rol_principal === 'administrador'
            && $usuario->estado_cuenta === 'activa' && ! $usuario->requiere_cambio_clave);

        Event::listen(CommandStarting::class, function (CommandStarting $event): void {
            if ($event->command === 'migrate' || str_starts_with($event->command ?? '', 'migrate:')
                || $event->command === 'db:wipe') {
                throw new RuntimeException('El esquema se administra con database/manage.py y las migraciones SQL del proyecto.');
            }
        });
    }
}
