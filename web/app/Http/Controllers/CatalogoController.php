<?php

namespace App\Http\Controllers;

use App\Http\Requests\Perfiles\FiltrarCatalogoRequest;
use App\Services\CatalogoService;
use App\Services\CoincidenciaService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\View\View;

class CatalogoController extends Controller
{
    public function __construct(
        private readonly CatalogoService $catalogo,
        private readonly CoincidenciaService $coincidencias,
    ) {}

    public function index(FiltrarCatalogoRequest $request): View
    {
        Gate::authorize('consultar-catalogo');
        $actor = (int) $request->user()->getAuthIdentifier();
        $filtros = $request->validated();
        $proyectos = $this->catalogo->listar($actor, $filtros, (int) ($filtros['page'] ?? 1));
        $rol = $request->user()->rol_principal;

        return view('catalogo.index', [
            'rol' => $rol,
            'proyectos' => $proyectos,
            'filtros' => $filtros,
            'opciones' => $this->catalogo->opciones($actor),
            'coincidencias' => $rol === 'alumno'
                ? $this->coincidencias->catalogo($actor, array_map(fn ($p) => (int) $p->id, $proyectos->items()))
                : [],
        ]);
    }

    public function show(Request $request, int $proyecto): View
    {
        Gate::authorize('consultar-catalogo');
        $actor = (int) $request->user()->getAuthIdentifier();
        $rol = $request->user()->rol_principal;
        $datos = $this->catalogo->obtener($actor, $proyecto);

        return view('catalogo.show', [
            'rol' => $rol,
            'proyecto' => $datos,
            'coincidencia' => $rol === 'alumno' ? ($this->coincidencias->catalogo($actor, [$proyecto])[$proyecto] ?? null) : null,
        ]);
    }
}
