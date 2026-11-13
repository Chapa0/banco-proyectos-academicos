<?php

namespace App\Http\Controllers;

use App\Http\Requests\Proyectos\EditarEmpresaRequest;
use App\Services\ImagenService;
use App\Services\PublicacionService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\View\View;

class EmpresaController extends Controller
{
    public function __construct(
        private readonly PublicacionService $publicacion,
        private readonly ImagenService $imagenes,
    ) {}

    public function edit(Request $request): View
    {
        Gate::authorize('gestionar-proyectos');

        $actor = (int) $request->user()->getAuthIdentifier();
        $empresa = $this->publicacion->empresa($actor);
        $id = (int) ($empresa->id ?? 0);

        return view('empresa.edit', ['empresa' => $empresa, 'logo' => $this->imagenes->mapa($actor, [], [$id])->logos[$id] ?? null]);
    }

    public function update(EditarEmpresaRequest $request): RedirectResponse
    {
        Gate::authorize('gestionar-proyectos');
        $this->publicacion->editarEmpresa((int) $request->user()->getAuthIdentifier(), $request->datos(), $request->validated('version'));

        return redirect()->route('empresa.edit')->with('status', 'Datos de la empresa actualizados.');
    }
}
