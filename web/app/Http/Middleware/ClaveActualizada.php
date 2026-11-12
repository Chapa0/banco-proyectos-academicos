<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class ClaveActualizada
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user()->requiere_cambio_clave) {
            return redirect()->route('clave.edit');
        }

        return $next($request);
    }
}
