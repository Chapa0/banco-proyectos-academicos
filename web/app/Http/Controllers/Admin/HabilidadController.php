<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Cuentas\GuardarHabilidadRequest;
use App\Services\HabilidadService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;
use Illuminate\View\View;

/** UX-10: catálogo de habilidades que usan perfiles, proyectos y la coincidencia. */
class HabilidadController extends Controller
{
    public function __construct(private readonly HabilidadService $habilidades) {}

    public function index(Request $request): View
    {
        Gate::authorize('administrar-cuentas');
        $filtros = $request->validate([
            'buscar' => ['nullable', 'string', 'max:100'],
            'tipo' => ['nullable', Rule::in(array_keys(HabilidadService::TIPOS))],
            'page' => ['nullable', 'integer', 'min:1', 'max:10000'],
        ]);
        [$lista, $resumen] = $this->habilidades->listar((int) $request->user()->getAuthIdentifier(), $filtros);

        return view('habilidades.index', ['habilidades' => $lista, 'resumen' => $resumen, 'filtros' => $filtros, 'tipos' => HabilidadService::TIPOS]);
    }

    public function store(GuardarHabilidadRequest $request): RedirectResponse
    {
        $datos = $request->validated();
        $this->habilidades->guardar((int) $request->user()->getAuthIdentifier(), null, $datos);

        return redirect()->route('habilidades.index', ['buscar' => $datos['nombre']])->with('status', 'Habilidad «'.$datos['nombre'].'» agregada al catálogo.');
    }

    public function update(GuardarHabilidadRequest $request, string $habilidad): RedirectResponse
    {
        $datos = $request->validated();
        $this->habilidades->guardar((int) $request->user()->getAuthIdentifier(), $this->identificadorRuta($habilidad), $datos);

        return redirect()->back()->with('status', 'Habilidad «'.$datos['nombre'].'» actualizada.');
    }

    public function destroy(Request $request, string $habilidad): RedirectResponse
    {
        Gate::authorize('administrar-cuentas');
        $this->habilidades->eliminar((int) $request->user()->getAuthIdentifier(), $this->identificadorRuta($habilidad));

        return redirect()->back()->with('status', 'Habilidad eliminada del catálogo.');
    }
}
