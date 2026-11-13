<?php

namespace App\Http\Controllers;

use App\Services\ConstanciaService;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Gate;

class ConstanciaController extends Controller
{
    public function __construct(private readonly ConstanciaService $constancias) {}

    public function show(Request $request, string $tipo, string $solicitud): Response
    {
        Gate::authorize('consultar-participacion');
        $datos = $this->constancias->datos((int) $request->user()->getAuthIdentifier(), $tipo, $this->identificadorRuta($solicitud));

        return response($this->constancias->pdf($datos), 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'attachment; filename="constancia-'.$datos->folio.'.pdf"',
            'Cache-Control' => 'private, no-store',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }
}
