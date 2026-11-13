<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Proyectos\ResolverProyectoRequest;
use App\Services\PublicacionService;
use App\Support\LineaTiempo;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;
use Illuminate\View\View;

class RevisionProyectoController extends Controller
{
    public function __construct(private readonly PublicacionService $publicacion) {}

    public function index(Request $request): View
    {
        Gate::authorize('revisar-proyectos');
        $filtros = $request->validate([
            'buscar' => ['nullable', 'string', 'max:100'],
            'estado' => ['nullable', Rule::in(array_keys(PublicacionService::ESTADOS))],
            'page' => ['nullable', 'integer', 'min:1', 'max:10000'],
        ]);
        if (! $request->has('estado')) {
            $filtros['estado'] = 'en_revision';
        }

        return view('revision.index', [
            'proyectos' => $this->publicacion->listar((int) $request->user()->getAuthIdentifier(), $filtros, (int) ($filtros['page'] ?? 1)),
            'filtros' => $filtros, 'estados' => PublicacionService::ESTADOS,
        ]);
    }

    public function show(Request $request, int $proyecto): View
    {
        Gate::authorize('revisar-proyectos');
        $actual = $this->publicacion->obtener((int) $request->user()->getAuthIdentifier(), $proyecto);

        return view('revision.show', [
            'proyecto' => $actual, 'estados' => PublicacionService::ESTADOS, 'lineaTiempo' => LineaTiempo::proyecto($actual->estado, $actual->revisiones ?? []),
            'puedeEditar' => false, 'puedeResolver' => $this->publicacion->puedeResolver($actual),
            'puedeEnviar' => false, 'ultimaRevision' => $this->publicacion->revisionActual($actual),
            'revisionActual' => $this->publicacion->revisionActual($actual),
        ]);
    }

    public function resolver(ResolverProyectoRequest $request, int $proyecto): RedirectResponse
    {
        Gate::authorize('revisar-proyectos');
        $this->publicacion->resolver((int) $request->user()->getAuthIdentifier(), $proyecto, $request->validated());
        $mensaje = match ($request->validated('resultado')) {
            'aprobada' => 'Proyecto publicado con la versión revisada y el cupo validado.',
            'en_correccion' => 'Proyecto devuelto a la empresa con el motivo de corrección.',
            'rechazada' => 'Proyecto rechazado. La decisión y su motivo quedaron registrados.',
        };

        return redirect()->route('revision.show', $proyecto)->with('status', $mensaje);
    }
}
