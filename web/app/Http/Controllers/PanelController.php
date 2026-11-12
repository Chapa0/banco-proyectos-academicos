<?php

namespace App\Http\Controllers;

use App\Services\PendienteService;
use App\Services\PerfilService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\View\View;
use Symfony\Component\HttpKernel\Exception\HttpException;

class PanelController extends Controller
{
    public function __construct(
        private readonly PerfilService $perfiles,
        private readonly PendienteService $pendientes,
    ) {}

    public function __invoke(Request $request): View
    {
        $actor = (int) $request->user()->getAuthIdentifier();
        $avance = null;
        if (Gate::allows('gestionar-perfil')) {
            try {
                $avance = $this->perfiles->completitud($this->perfiles->obtener($actor));
            } catch (HttpException) {
                // El avance es una ayuda; el panel se muestra aunque no pueda calcularse.
            }
        }

        return view('panel', [
            'usuario' => $request->user(), 'avancePerfil' => $avance,
            'pendientes' => $this->pendientes->delActor($actor, $request->user()->rol_principal),
        ]);
    }
}
