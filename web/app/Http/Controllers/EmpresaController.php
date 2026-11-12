<?php

namespace App\Http\Controllers;

use App\Http\Requests\Proyectos\EditarEmpresaRequest;
use App\Services\PublicacionService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\View\View;

class EmpresaController extends Controller
{
    public function __construct(private readonly PublicacionService $publicacion) {}

    public function edit(Request $request): View
    {
        Gate::authorize('gestionar-proyectos');

        return view('empresa.edit', ['empresa' => $this->publicacion->empresa((int) $request->user()->getAuthIdentifier())]);
    }

    public function update(EditarEmpresaRequest $request): RedirectResponse
    {
        Gate::authorize('gestionar-proyectos');
        $this->publicacion->editarEmpresa((int) $request->user()->getAuthIdentifier(), $request->datos(), $request->validated('version'));

        return redirect()->route('empresa.edit')->with('status', 'Datos de la empresa actualizados.');
    }
}
