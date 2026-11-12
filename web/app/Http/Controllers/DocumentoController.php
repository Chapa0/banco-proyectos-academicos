<?php

namespace App\Http\Controllers;

use App\Http\Requests\Perfiles\SubirDocumentoRequest;
use App\Services\DocumentoService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\ResponseHeaderBag;

class DocumentoController extends Controller
{
    public function __construct(private readonly DocumentoService $documentos) {}

    public function store(SubirDocumentoRequest $request): RedirectResponse
    {
        $datos = $request->validated();
        $this->documentos->subir((int) $request->user()->getAuthIdentifier(), $datos['tipo'],
            isset($datos['habilidad_id']) ? (int) $datos['habilidad_id'] : null, $request->file('archivo'));

        return redirect()->to(route('perfil.edit').'#documentos')->with('status', $datos['tipo'] === 'curriculum'
            ? 'Currículum guardado. Las empresas lo verán al revisar tus solicitudes.'
            : 'Evidencia guardada en tu habilidad.');
    }

    public function destroy(Request $request, int $documento): RedirectResponse
    {
        Gate::authorize('gestionar-perfil');
        $this->documentos->retirar((int) $request->user()->getAuthIdentifier(), $documento);

        return redirect()->to(route('perfil.edit').'#documentos')->with('status', 'Archivo quitado de tu perfil.');
    }

    /** Descarga como adjunto, nunca en línea: el navegador no ejecuta ni muestra el PDF dentro del sitio. */
    public function show(Request $request, int $documento): BinaryFileResponse
    {
        $datos = $this->documentos->abrir((int) $request->user()->getAuthIdentifier(), $documento);

        return response()->download($this->documentos->ruta($datos), $datos->nombre_original, [
            'Content-Type' => 'application/pdf',
            'X-Content-Type-Options' => 'nosniff',
            'Cache-Control' => 'private, no-store',
            'Content-Security-Policy' => "default-src 'none'; sandbox",
        ], ResponseHeaderBag::DISPOSITION_ATTACHMENT);
    }
}
