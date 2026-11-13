<?php

namespace App\Http\Controllers;

use App\Http\Requests\Participacion\EnviarParticipacionRequest;
use App\Http\Requests\Participacion\FiltrarParticipacionRequest;
use App\Http\Requests\Participacion\OperarParticipacionRequest;
use App\Services\CoincidenciaService;
use App\Services\DocumentoService;
use App\Services\ImagenService;
use App\Services\ParticipacionService;
use App\Services\PublicacionService;
use App\Support\LineaTiempo;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\View\View;
use Symfony\Component\HttpKernel\Exception\HttpException;

class ParticipacionController extends Controller
{
    public function __construct(
        private readonly ParticipacionService $participacion,
        private readonly PublicacionService $publicacion,
        private readonly CoincidenciaService $coincidencias,
        private readonly DocumentoService $documentos,
        private readonly ImagenService $imagenes,
    ) {}

    public function index(FiltrarParticipacionRequest $request, string $tipo): View
    {
        Gate::authorize('consultar-participacion');
        $filtros = $request->validated();

        return view('participacion.index', [
            'solicitudes' => $this->participacion->listar((int) $request->user()->getAuthIdentifier(), $tipo, $filtros),
            'tipo' => $tipo, 'tipos' => ParticipacionService::TIPOS,
            'rol' => $request->user()->rol_principal, 'filtros' => $filtros,
            'estados' => $this->participacion->estados($tipo), 'estadosProyecto' => PublicacionService::ESTADOS,
        ]);
    }

    public function create(Request $request, string $proyecto): View
    {
        Gate::authorize('participar');
        $proyecto = $this->identificadorRuta($proyecto);
        $rol = $request->user()->rol_principal;

        return view('participacion.create', [
            'contexto' => $this->participacion->contexto((int) $request->user()->getAuthIdentifier(), $proyecto),
            'tipo' => $rol === 'alumno' ? 'candidatura' : 'direccion', 'rol' => $rol,
            'estados' => PublicacionService::ESTADOS,
        ]);
    }

    public function store(EnviarParticipacionRequest $request, string $proyecto): RedirectResponse
    {
        Gate::authorize('participar');
        $proyecto = $this->identificadorRuta($proyecto);
        $solicitud = $this->participacion->enviar(
            (int) $request->user()->getAuthIdentifier(), $proyecto, $request->datos(), $request->validated('version'),
        );
        $tipo = $request->user()->rol_principal === 'alumno' ? 'candidatura' : 'direccion';

        return redirect()->route('participacion.show', [$tipo, $solicitud])->with('status', $tipo === 'candidatura'
            ? 'Candidatura enviada. Puedes consultar su estado y seguimiento.'
            : 'Solicitud de dirección enviada. Puedes consultar su estado y seguimiento.');
    }

    public function show(Request $request, string $tipo, string $solicitud): View
    {
        Gate::authorize('consultar-participacion');

        $solicitud = $this->identificadorRuta($solicitud);
        $actor = (int) $request->user()->getAuthIdentifier();
        $rol = $request->user()->rol_principal;
        $detalle = $this->participacion->obtener($actor, $tipo, $solicitud);

        return view('participacion.show', [
            'detalle' => $detalle, 'lineaTiempo' => LineaTiempo::participacion($tipo, $detalle),
            'tipo' => $tipo, 'tipos' => ParticipacionService::TIPOS, 'rol' => $rol,
            'estados' => $this->participacion->estados($tipo), 'estadosProyecto' => PublicacionService::ESTADOS,
            'coincidencia' => $tipo === 'candidatura' && in_array($rol, ['empresa', 'administrador'], true)
                ? $this->coincidenciaCandidato($actor, $detalle) : null,
            'documentos' => $this->documentos->mapa($actor, [$detalle->perfil ?? null]),
            'imagenes' => $this->imagenes->mapa($actor, [$detalle->perfil->usuario_id ?? null]),
            // Solo orienta la vista; el permiso real lo comprueba banco.web_constancia al descargar.
            'constanciaDisponible' => in_array($rol, ['administrador', 'alumno', 'profesor'], true)
                && ($detalle->asignacion->estado ?? null) === 'finalizada' && ($detalle->proyecto->estado ?? null) === 'finalizado',
        ]);
    }

    /** Ayuda para evaluar: habilidades del proyecto frente a las del perfil ya autorizado (UX-02). */
    private function coincidenciaCandidato(int $actor, object $detalle): ?object
    {
        if (! isset($detalle->perfil->habilidades, $detalle->proyecto->id)) {
            return null;
        }
        try {
            $proyecto = $this->publicacion->obtener($actor, (int) $detalle->proyecto->id);
        } catch (HttpException) {
            return null;
        }

        // Igual que el catálogo: se compara con la versión publicada que vio el alumno al postularse.
        $publicada = collect($proyecto->revisiones ?? [])->firstWhere('id', $proyecto->revision_publicada_id ?? null);
        $requeridas = $publicada->instantanea_contenido->habilidades ?? $proyecto->habilidades ?? [];

        return $this->coincidencias->calcular($requeridas, $detalle->perfil->habilidades);
    }

    public function operar(OperarParticipacionRequest $request, string $tipo, string $solicitud, string $accion): RedirectResponse
    {
        Gate::authorize('consultar-participacion');
        $solicitud = $this->identificadorRuta($solicitud);
        $this->participacion->operar(
            (int) $request->user()->getAuthIdentifier(), $tipo, $solicitud, $accion,
            $request->datos(), $request->validated('version'),
        );
        $mensaje = match ($accion) {
            'cancelar' => 'Solicitud cancelada. Su historial se conserva.',
            'evaluar' => 'Evaluación registrada. La preselección requiere una acción posterior.',
            'preseleccionar' => 'Candidatura preseleccionada para revisión administrativa.',
            'aprobar' => 'Solicitud aprobada y asignación registrada.',
            'rechazar' => 'Solicitud rechazada. La decisión y su motivo quedaron registrados.',
        };

        return redirect()->route('participacion.show', [$tipo, $solicitud])->with('status', $mensaje);
    }
}
