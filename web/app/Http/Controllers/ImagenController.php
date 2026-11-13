<?php

namespace App\Http\Controllers;

use App\Http\Requests\Perfiles\SubirImagenRequest;
use App\Services\ImagenService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

/** UX-08: foto de perfil (alumno/profesor) y logo de empresa. */
class ImagenController extends Controller
{
    public function __construct(private readonly ImagenService $imagenes) {}

    public function guardarFoto(SubirImagenRequest $request): RedirectResponse
    {
        $this->imagenes->subir((int) $request->user()->getAuthIdentifier(), 'foto', $request->file('imagen'));

        return redirect()->to(route('perfil.edit').'#foto')->with('status', 'Foto de perfil actualizada.');
    }

    public function quitarFoto(Request $request): RedirectResponse
    {
        $this->imagenes->retirar((int) $request->user()->getAuthIdentifier(), 'foto');

        return redirect()->to(route('perfil.edit').'#foto')->with('status', 'Se quitó la foto de perfil.');
    }

    public function guardarLogo(SubirImagenRequest $request): RedirectResponse
    {
        $this->imagenes->subir((int) $request->user()->getAuthIdentifier(), 'logo', $request->file('imagen'));

        return redirect()->to(route('empresa.edit').'#logo')->with('status', 'Logo de la empresa actualizado.');
    }

    public function quitarLogo(Request $request): RedirectResponse
    {
        $this->imagenes->retirar((int) $request->user()->getAuthIdentifier(), 'logo');

        return redirect()->to(route('empresa.edit').'#logo')->with('status', 'Se quitó el logo de la empresa.');
    }

    public function show(Request $request, string $imagen): BinaryFileResponse
    {
        [$ruta, $etiqueta] = $this->imagenes->abrir((int) $request->user()->getAuthIdentifier(), $this->identificadorRuta($imagen));

        return response()->file($ruta, [
            'Content-Type' => 'image/webp',
            'Cache-Control' => 'private, max-age=86400',
            'ETag' => '"'.$etiqueta.'"',
            'X-Content-Type-Options' => 'nosniff',
            'Content-Security-Policy' => "default-src 'none'; sandbox",
        ]);
    }
}
