<?php

namespace App\Providers;

use App\Auth\UsuarioProvider;
use App\Models\Usuario;
use App\Services\ConsultaService;
use App\Services\ImagenService;
use Illuminate\Console\Events\CommandStarting;
use Illuminate\Foundation\Console\ServeCommand;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\View;
use Illuminate\Support\ServiceProvider;
use RuntimeException;
use Throwable;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // `artisan serve` solo transmite al servidor algunas variables de entorno. Sin TEMP/TMP,
        // PHP en Windows no tiene carpeta temporal: fallan la subida de imágenes y el PDF.
        array_push(ServeCommand::$passthroughVariables, 'TEMP', 'TMP', 'TMPDIR');
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Auth::provider('banco', fn () => new UsuarioProvider);
        // UX-08: foto propia en el menú de cuenta (alumno y profesor). Si falla, se muestran iniciales.
        View::composer('layouts.app', function ($view) {
            $usuario = auth()->user();
            $foto = null;
            if ($usuario && ! $usuario->requiere_cambio_clave && in_array($usuario->rol_principal, ['alumno', 'profesor'], true)) {
                $id = (int) $usuario->getAuthIdentifier();
                $foto = app(ImagenService::class)->mapa($id, [$id])->fotos[$id] ?? null;
            }
            $view->with('fotoCuenta', $foto);
            // RD-01: contador de avisos sin leer en la barra lateral y la campana. Es una ayuda: si falla, no se muestra.
            $sinLeer = null;
            if ($usuario && ! $usuario->requiere_cambio_clave && Gate::forUser($usuario)->allows('consultar-avisos')) {
                try {
                    $sinLeer = (int) app(ConsultaService::class)->avisos((int) $usuario->getAuthIdentifier(), ['estado' => 'no_leidos'])->no_leidos;
                } catch (Throwable) {
                    $sinLeer = null;
                }
            }
            $view->with('avisosSinLeer', $sinLeer);
        });
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
