<?php

namespace App\Http\Controllers;

use App\Http\Requests\Participacion\FiltrarParticipacionRequest;
use App\Http\Requests\Participacion\OperarParticipacionRequest;
use App\Services\DocumentoService;
use App\Services\ImagenService;
use App\Services\ParticipacionService;
use App\Services\PublicacionService;
use App\Support\LineaTiempo;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\View\View;

class SeguimientoController extends Controller
{
    public function __construct(
        private readonly ParticipacionService $participacion,
        private readonly DocumentoService $documentos,
        private readonly ImagenService $imagenes,
    ) {}

    public function index(FiltrarParticipacionRequest $request): View
    {
        Gate::authorize('consultar-participacion');
        $filtros = $request->validated();

        return view('seguimiento.index', [
            'proyectos' => $this->participacion->proyectos((int) $request->user()->getAuthIdentifier(), $filtros),
            'rol' => $request->user()->rol_principal, 'filtros' => $filtros, 'estados' => PublicacionService::ESTADOS,
        ]);
    }

    public function show(Request $request, string $proyecto): View
    {
        Gate::authorize('consultar-participacion');
        $proyecto = $this->identificadorRuta($proyecto);

        $actor = (int) $request->user()->getAuthIdentifier();
        $detalle = $this->participacion->proyecto($actor, $proyecto);
        $perfiles = collect(array_merge($detalle->alumnos ?? [], $detalle->directores ?? []))->pluck('perfil')->filter();

        return view('seguimiento.show', [
            'detalle' => $detalle, 'lineaTiempo' => LineaTiempo::proyecto($detalle->proyecto->estado, [], $detalle->historial ?? []),
            'rol' => $request->user()->rol_principal, 'estados' => PublicacionService::ESTADOS,
            'documentos' => $this->documentos->mapa($actor, $perfiles),
            'imagenes' => $this->imagenes->mapa($actor, $perfiles->pluck('usuario_id')->all()),
        ]);
    }

    public function operar(OperarParticipacionRequest $request, string $proyecto, string $accion): RedirectResponse
    {
        Gate::authorize('gestionar-ciclo');
        $proyecto = $this->identificadorRuta($proyecto);
        $this->participacion->operarProyecto(
            (int) $request->user()->getAuthIdentifier(), $proyecto, $accion,
            $request->datos(), $request->validated('version'),
        );
        $mensaje = match ($accion) {
            'iniciar' => 'Inicio del proyecto confirmado.', 'reanudar' => 'Reanudación del proyecto confirmada.',
            'finalizar' => 'Proyecto finalizado. Sus participaciones se cerraron coordinadamente.',
            'cancelar' => 'Proyecto cancelado. Sus participaciones se cerraron coordinadamente.',
            'retirar_alumno', 'retirar_director' => 'Retiro registrado. El proyecto se pausa si pierde los participantes mínimos.',
        };

        return redirect()->route('seguimiento.show', $proyecto)->with('status', $mensaje);
    }
}
