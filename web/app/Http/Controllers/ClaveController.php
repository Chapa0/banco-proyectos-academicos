<?php

namespace App\Http\Controllers;

use App\Http\Requests\CambiarClaveRequest;
use Illuminate\Database\DeadlockException;
use Illuminate\Database\QueryException;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;

class ClaveController extends Controller
{
    public function edit(): View
    {
        return view('auth.clave');
    }

    public function update(CambiarClaveRequest $request): RedirectResponse
    {
        if (! Hash::check($request->validated('current_password'), $request->user()->getAuthPassword())) {
            throw ValidationException::withMessages(['current_password' => 'La contraseña actual no es correcta.']);
        }
        if (Hash::check($request->validated('password'), $request->user()->getAuthPassword())) {
            throw ValidationException::withMessages(['password' => 'Elige una contraseña distinta de la actual.']);
        }

        try {
            DB::transaction(fn () => DB::select('SELECT banco.web_cambiar_clave(?,?,?)', [
                $request->user()->id, Hash::make($request->validated('password')), $request->user()->version_acceso,
            ]));
        } catch (QueryException|DeadlockException $error) {
            $origen = $error instanceof DeadlockException ? $error->getPrevious() : $error;
            if ($origen instanceof QueryException && in_array((string) $origen->getCode(), ['40001', '40P01'], true)) {
                throw ValidationException::withMessages(['current_password' => 'La cuenta cambió. Vuelve a iniciar sesión.']);
            }
            throw $error;
        }

        $usuario = Auth::getProvider()->retrieveById($request->user()->id);
        Auth::setUser($usuario);
        $request->session()->regenerate();
        $request->session()->regenerateToken();
        $request->session()->put('acceso_version', $usuario->version_acceso);

        return redirect()->route('panel')->with('status', 'Contraseña actualizada. Las otras sesiones quedaron cerradas.');
    }
}
