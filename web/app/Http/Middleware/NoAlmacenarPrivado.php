<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class NoAlmacenarPrivado
{
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);
        if ($request->is('login', 'panel', 'clave', 'admin/*') || $request->user()) {
            $response->headers->set('Cache-Control', 'no-store, private');
        }
        $response->headers->set('X-Content-Type-Options', 'nosniff');
        $response->headers->set('X-Frame-Options', 'DENY');

        return $response;
    }
}
