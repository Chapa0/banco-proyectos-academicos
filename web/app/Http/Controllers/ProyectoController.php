<?php

namespace App\Http\Controllers;

use App\Http\Requests\Proyectos\EnviarProyectoRequest;
use App\Http\Requests\Proyectos\GuardarProyectoRequest;
use App\Services\PublicacionService;
use App\Support\LineaTiempo;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;
use Illuminate\View\View;

class ProyectoController extends Controller
{
    public function __construct(private readonly PublicacionService $publicacion) {}

    public function index(Request $request): View
    {
        Gate::authorize('gestionar-proyectos');
        $filtros = $request->validate([
            'buscar' => ['nullable', 'string', 'max:100'],
            'estado' => ['nullable', Rule::in(array_keys(PublicacionService::ESTADOS))],
            'page' => ['nullable', 'integer', 'min:1', 'max:10000'],
        ]);

        return view('proyectos.index', [
            'proyectos' => $this->publicacion->listar((int) $request->user()->getAuthIdentifier(), $filtros, (int) ($filtros['page'] ?? 1)),
            'filtros' => $filtros, 'estados' => PublicacionService::ESTADOS,
        ]);
    }

    public function create(Request $request): View
    {
        Gate::authorize('gestionar-proyectos');
        $actor = (int) $request->user()->getAuthIdentifier();

        return view('proyectos.create', [
            'empresa' => $this->publicacion->empresa($actor),
            'habilidades' => $this->publicacion->habilidades($actor),
        ]);
    }

    public function store(GuardarProyectoRequest $request): RedirectResponse
    {
        Gate::authorize('gestionar-proyectos');
        $proyecto = $this->publicacion->crear((int) $request->user()->getAuthIdentifier(), $request->datos());

        return redirect()->route('proyectos.show', $proyecto)->with('status', 'Borrador guardado. Completa su contenido y envíalo a revisión cuando esté listo.');
    }

    public function show(Request $request, int $proyecto): View
    {
        Gate::authorize('gestionar-proyectos');
        $actual = $this->publicacion->obtener((int) $request->user()->getAuthIdentifier(), $proyecto);

        return view('proyectos.show', [
            'proyecto' => $actual, 'estados' => PublicacionService::ESTADOS, 'lineaTiempo' => LineaTiempo::proyecto($actual->estado, $actual->revisiones ?? []),
            'puedeEditar' => $this->publicacion->puedeEditar($actual),
            'puedeEnviar' => $this->publicacion->puedeEditar($actual),
            'ultimaRevision' => $this->publicacion->revisionActual($actual),
            'puedeResolver' => false, 'revisionActual' => $this->publicacion->revisionActual($actual),
        ]);
    }

    public function edit(Request $request, int $proyecto): View
    {
        Gate::authorize('gestionar-proyectos');
        $actor = (int) $request->user()->getAuthIdentifier();
        $actual = $this->publicacion->obtener($actor, $proyecto);
        abort_unless($this->publicacion->puedeEditar($actual), 403);

        return view('proyectos.edit', [
            'proyecto' => $actual, 'empresa' => $actual->empresa,
            'habilidades' => $this->publicacion->habilidades($actor),
            'estados' => PublicacionService::ESTADOS,
            'ultimaRevision' => $this->publicacion->revisionActual($actual),
            'revisionActual' => $this->publicacion->revisionActual($actual),
            'puedeEditar' => true, 'puedeEnviar' => true, 'puedeResolver' => false,
        ]);
    }

    public function update(GuardarProyectoRequest $request, int $proyecto): RedirectResponse
    {
        Gate::authorize('gestionar-proyectos');
        $this->publicacion->editar((int) $request->user()->getAuthIdentifier(), $proyecto, $request->datos(), $request->validated('version'));

        return redirect()->route('proyectos.show', $proyecto)->with('status', 'Cambios guardados. Envía el proyecto para que el administrador revise esta versión.');
    }

    public function enviar(EnviarProyectoRequest $request, int $proyecto): RedirectResponse
    {
        Gate::authorize('gestionar-proyectos');
        $this->publicacion->enviar((int) $request->user()->getAuthIdentifier(), $proyecto, $request->validated('version'));

        return redirect()->route('proyectos.show', $proyecto)->with('status', 'Proyecto enviado a revisión. El contenido quedará reservado hasta la resolución del administrador.');
    }
}
