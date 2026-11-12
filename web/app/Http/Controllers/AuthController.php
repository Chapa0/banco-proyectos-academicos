<?php

namespace App\Http\Controllers;

use App\Http\Requests\LoginRequest;
use Illuminate\Database\QueryException;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;
use Symfony\Component\HttpFoundation\Response;

class AuthController extends Controller
{
    public function create(): View
    {
        return view('auth.login');
    }

    public function store(LoginRequest $request): RedirectResponse|Response
    {
        $key = 'login:'.hash('sha256', $request->validated('correo').'|'.$request->ip());
        $ipKey = 'login-ip:'.hash('sha256', $request->ip());
        if (RateLimiter::tooManyAttempts($key, 5) || RateLimiter::tooManyAttempts($ipKey, 20)) {
            return response()->view('auth.login', [
                'mensajeLimite' => 'Demasiados intentos. Espera un minuto y vuelve a intentarlo.',
                'correoLogin' => $request->validated('correo'),
            ], 429)->header('Retry-After', max(RateLimiter::availableIn($key), RateLimiter::availableIn($ipKey), 1));
        }

        if (! Auth::attempt(['correo_normalizado' => $request->validated('correo'), 'password' => $request->validated('password')])) {
            RateLimiter::hit($key, 60);
            RateLimiter::hit($ipKey, 60);
            Log::notice('Intento de acceso rechazado.', ['referencia' => $key]);
            throw ValidationException::withMessages(['correo' => 'No fue posible iniciar sesión con esos datos.']);
        }

        try {
            DB::select('SELECT banco.web_registrar_acceso(?,?,?)', [$request->user()->id, $request->user()->version_acceso, 'inicio_sesion']);
        } catch (QueryException) {
            Auth::logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();
            throw ValidationException::withMessages(['correo' => 'No fue posible iniciar sesión con esos datos.']);
        }

        RateLimiter::clear($key);
        $request->session()->regenerate();
        $request->session()->put('acceso_version', $request->user()->version_acceso);

        return redirect()->route($request->user()->requiere_cambio_clave ? 'clave.edit' : 'panel');
    }

    public function destroy(Request $request): RedirectResponse
    {
        try {
            DB::select('SELECT banco.web_registrar_acceso(?,?,?)', [$request->user()->id, $request->user()->version_acceso, 'cierre_sesion']);
        } catch (QueryException) {
            // El cierre local debe completarse aunque falle el registro.
            Log::warning('No se pudo registrar el cierre de una sesión.');
        }
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect()->route('login')->with('status', 'Sesión cerrada.');
    }
}
