<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

class CuentaActiva
{
    public function handle(Request $request, Closure $next): Response
    {
        // Se consulta en cada petición, incluso si el guard conserva una
        // instancia en memoria durante pruebas o un proceso persistente.
        $usuario = Auth::getProvider()->retrieveById(Auth::id());
        if ($usuario === null || $usuario->estado_cuenta !== 'activa'
            || (string) $request->session()->get('acceso_version') !== (string) $usuario->version_acceso) {
            Auth::logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();

            return redirect()->route('login')->withErrors(['correo' => 'La sesión terminó. Vuelve a iniciar sesión.']);
        }

        Auth::setUser($usuario);

        return $next($request);
    }
}
