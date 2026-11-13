<?php

use App\Http\Middleware\ClaveActualizada;
use App\Http\Middleware\CuentaActiva;
use App\Http\Middleware\NoAlmacenarPrivado;
use Illuminate\Database\DeadlockException;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        if (env('BANCO_TUNEL_PUBLICO', false)) {
            // cloudflared llega al servidor de pruebas exclusivamente por loopback.
            $middleware->trustProxies(
                at: ['127.0.0.1', '::1'],
                headers: Request::HEADER_X_FORWARDED_FOR | Request::HEADER_X_FORWARDED_PROTO | Request::HEADER_X_FORWARDED_PORT,
            );
        }

        $middleware->alias([
            'cuenta.activa' => CuentaActiva::class,
            'clave.actualizada' => ClaveActualizada::class,
        ]);
        $middleware->web(append: [NoAlmacenarPrivado::class]);
        $middleware->redirectGuestsTo(fn () => route('login'));
        $middleware->redirectUsersTo(fn () => route('panel'));
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->report(function (DeadlockException $error) {
            Log::warning('La operación encontró un conflicto de transacción.');

            return false;
        });
        $exceptions->render(fn (DeadlockException $error) => response()->view('errors.503', [], 503));
        $exceptions->report(function (QueryException $error) {
            // Una excepción SQL puede incluir bindings con hashes o correos.
            Log::error('Falló una operación de base de datos.', ['sqlstate' => $error->errorInfo[0] ?? 'desconocido']);

            return false;
        });
        $exceptions->render(function (QueryException $error, Request $request) {
            return response()->view('errors.503', [], 503);
        });
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
    })->create();
