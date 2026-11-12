<?php

namespace App\Http\Controllers;

use App\Http\Requests\Consultas\FiltrarAvisosRequest;
use App\Http\Requests\Consultas\MarcarAvisoRequest;
use App\Services\ConsultaService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\View\View;

class AvisoController extends Controller
{
    public function __construct(private readonly ConsultaService $consultas) {}

    public function index(FiltrarAvisosRequest $request): View
    {
        Gate::authorize('consultar-avisos');
        $filtros = $request->validated();
        $datos = $this->consultas->avisos((int) $request->user()->getAuthIdentifier(), $filtros);

        return view('avisos.index', [
            'avisos' => $datos->pagina, 'noLeidos' => (int) $datos->no_leidos,
            'filtros' => $filtros, 'estados' => ConsultaService::ESTADOS_AVISO,
        ]);
    }

    public function show(Request $request, string $aviso): View
    {
        Gate::authorize('consultar-avisos');
        $datos = $this->consultas->aviso((int) $request->user()->getAuthIdentifier(), $this->identificadorRuta($aviso));

        return view('avisos.show', [
            'aviso' => $datos->aviso, 'enlace' => $this->enlace($datos->recurso, $request->user()->rol_principal),
        ]);
    }

    public function leer(MarcarAvisoRequest $request, string $aviso): RedirectResponse
    {
        Gate::authorize('consultar-avisos');
        $aviso = $this->identificadorRuta($aviso);
        $this->consultas->leerAviso((int) $request->user()->getAuthIdentifier(), $aviso);

        return redirect()->route('avisos.show', $aviso)->with('status', 'Aviso marcado como leído.');
    }

    private function enlace(?object $recurso, string $rol): ?array
    {
        if ($recurso === null) {
            return null;
        }
        $ruta = match ($recurso->tipo) {
            'candidatura' => ['participacion.show', ['tipo' => 'candidatura', 'solicitud' => $recurso->id], 'Consultar candidatura'],
            'direccion' => ['participacion.show', ['tipo' => 'direccion', 'solicitud' => $recurso->id], 'Consultar solicitud de dirección'],
            'proyecto' => match (true) {
                ($recurso->contexto ?? '') !== 'publicacion' => ['seguimiento.show', ['proyecto' => $recurso->id], 'Consultar proyecto'],
                $rol === 'administrador' => ['revision.show', ['proyecto' => $recurso->id], 'Revisar proyecto'],
                $rol === 'empresa' => ['proyectos.show', ['proyecto' => $recurso->id], 'Consultar proyecto'],
                default => ['seguimiento.show', ['proyecto' => $recurso->id], 'Consultar proyecto'],
            },
            default => null,
        };

        return $ruta === null ? null : ['url' => route($ruta[0], $ruta[1]), 'texto' => $ruta[2]];
    }
}
