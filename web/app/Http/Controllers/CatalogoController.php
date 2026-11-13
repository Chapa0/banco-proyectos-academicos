<?php

namespace App\Http\Controllers;

use App\Http\Requests\Perfiles\FiltrarCatalogoRequest;
use App\Services\CatalogoService;
use App\Services\CoincidenciaService;
use App\Services\ImagenService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\View\View;

class CatalogoController extends Controller
{
    public function __construct(
        private readonly CatalogoService $catalogo,
        private readonly CoincidenciaService $coincidencias,
        private readonly ImagenService $imagenes,
    ) {}

    public function index(FiltrarCatalogoRequest $request): View
    {
        Gate::authorize('consultar-catalogo');
        $actor = (int) $request->user()->getAuthIdentifier();
        $filtros = $request->validated();
        $proyectos = $this->catalogo->listar($actor, $filtros, (int) ($filtros['page'] ?? 1));
        $rol = $request->user()->rol_principal;

        // Recomendados solo en la vista inicial: con filtros o en otra página el alumno ya está buscando algo concreto.
        $recomendados = $rol === 'alumno' && array_filter($filtros, fn ($v) => $v !== null && $v !== '') === []
            ? $this->coincidencias->recomendaciones($actor, 3)
            : [];
        $ids = array_merge(array_map(fn ($p) => (int) $p->id, $proyectos->items()), array_map(fn ($p) => (int) $p->id, $recomendados));

        return view('catalogo.index', [
            'rol' => $rol,
            'logos' => $this->imagenes->mapa($actor, [], [], $ids)->logos_proyecto,
            'proyectos' => $proyectos,
            'filtros' => $filtros,
            'opciones' => $this->catalogo->opciones($actor),
            'coincidencias' => $rol === 'alumno'
                ? $this->coincidencias->catalogo($actor, array_map(fn ($p) => (int) $p->id, $proyectos->items()))
                : [],
            'recomendados' => $recomendados,
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
            'logo' => $this->imagenes->mapa($actor, [], [], [$proyecto])->logos_proyecto[$proyecto] ?? null,
            'coincidencia' => $rol === 'alumno' ? ($this->coincidencias->catalogo($actor, [$proyecto])[$proyecto] ?? null) : null,
        ]);
    }
}
