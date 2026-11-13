<?php

namespace App\Http\Controllers;

use App\Http\Requests\Perfiles\GuardarPerfilRequest;
use App\Services\DocumentoService;
use App\Services\ImagenService;
use App\Services\PerfilService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\View\View;

class PerfilController extends Controller
{
    public function __construct(
        private readonly PerfilService $perfiles,
        private readonly DocumentoService $documentos,
        private readonly ImagenService $imagenes,
    ) {}

    public function edit(Request $request): View
    {
        Gate::authorize('gestionar-perfil');
        $actor = (int) $request->user()->getAuthIdentifier();
        $actual = $this->perfiles->obtener($actor);

        return view('perfil.edit', [
            'rol' => $actual->rol,
            'perfil' => $actual->perfil,
            'habilidades' => $actual->rol === 'alumno' ? $this->perfiles->habilidades($actor) : [],
            'habilidadesPerfil' => $actual->habilidades,
            'version' => $actual->version,
            'avance' => $this->perfiles->completitud($actual),
            'documentos' => $this->documentos->delPerfil($actor, $actor),
            'foto' => $this->imagenes->mapa($actor, [$actor])->fotos[$actor] ?? null,
        ]);
    }

    public function update(GuardarPerfilRequest $request): RedirectResponse
    {
        Gate::authorize('gestionar-perfil');
        $this->perfiles->guardar((int) $request->user()->getAuthIdentifier(), $request->datos(), $request->validated('version'));

        return redirect()->route('perfil.edit')->with('status', 'Perfil actualizado.');
    }
}
