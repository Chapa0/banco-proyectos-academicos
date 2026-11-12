<?php

namespace App\Services;

use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * Tareas que esperan una acción de la cuenta (UX-05). Reutiliza los gateways de listado
 * ya concedidos, por lo que cada conteo respeta la misma pertenencia y privacidad que la lista enlazada.
 */
class PendienteService
{
    public function __construct(
        private readonly PublicacionService $publicacion,
        private readonly ParticipacionService $participacion,
        private readonly ConsultaService $consultas,
    ) {}

    /** @return list<array{clave:string,cantidad:int,texto:string,accion:string,url:string}> */
    public function delActor(int $actor, string $rol): array
    {
        $definiciones = match ($rol) {
            'administrador' => [
                ['revision', 'revisar-proyectos', fn () => $this->publicacion->listar($actor, ['estado' => 'en_revision'], 1)->total(),
                    ['proyecto enviado espera revisión', 'proyectos enviados esperan revisión'], 'Revisar', route('revision.index', ['estado' => 'en_revision'])],
                ['candidaturas', 'consultar-participacion', fn () => $this->participacion->listar($actor, 'candidatura', ['estado' => 'preseleccionada'])->total(),
                    ['candidatura preseleccionada espera resolución', 'candidaturas preseleccionadas esperan resolución'], 'Resolver', route('participacion.index', ['candidatura', 'estado' => 'preseleccionada'])],
                ['direcciones', 'consultar-participacion', fn () => $this->participacion->listar($actor, 'direccion', ['estado' => 'pendiente'])->total(),
                    ['solicitud de dirección espera resolución', 'solicitudes de dirección esperan resolución'], 'Resolver', route('participacion.index', ['direccion', 'estado' => 'pendiente'])],
            ],
            'empresa' => [
                ['evaluacion', 'consultar-participacion', fn () => $this->participacion->listar($actor, 'candidatura', ['estado' => 'pendiente_evaluacion'])->total(),
                    ['candidatura por evaluar', 'candidaturas por evaluar'], 'Evaluar', route('participacion.index', ['candidatura', 'estado' => 'pendiente_evaluacion'])],
                ['preseleccion', 'consultar-participacion', fn () => $this->participacion->listar($actor, 'candidatura', ['estado' => 'evaluada'])->total(),
                    ['candidatura evaluada puede preseleccionarse', 'candidaturas evaluadas pueden preseleccionarse'], 'Revisar', route('participacion.index', ['candidatura', 'estado' => 'evaluada'])],
                ['correccion', 'gestionar-proyectos', fn () => $this->publicacion->listar($actor, ['estado' => 'en_correccion'], 1)->total(),
                    ['proyecto devuelto necesita correcciones', 'proyectos devueltos necesitan correcciones'], 'Corregir', route('proyectos.index', ['estado' => 'en_correccion'])],
            ],
            default => [],
        };
        $definiciones[] = ['avisos', 'consultar-avisos', fn () => (int) $this->consultas->avisos($actor, ['estado' => 'no_leidos'])->no_leidos,
            ['aviso sin leer', 'avisos sin leer'], 'Leer', route('avisos.index', ['estado' => 'no_leidos'])];

        $pendientes = [];
        foreach ($definiciones as [$clave, $permiso, $contar, [$singular, $plural], $accion, $url]) {
            if (! Gate::allows($permiso)) {
                continue;
            }
            try {
                $cantidad = (int) $contar();
            } catch (HttpException $error) {
                // Un conteo es una ayuda: si falla, el panel se muestra sin ese pendiente.
                Log::warning('No fue posible calcular un pendiente del panel.', ['pendiente' => $clave, 'estado' => $error->getStatusCode()]);

                continue;
            }
            if ($cantidad > 0) {
                $pendientes[] = ['clave' => $clave, 'cantidad' => $cantidad, 'texto' => $cantidad === 1 ? $singular : $plural, 'accion' => $accion, 'url' => $url];
            }
        }

        return $pendientes;
    }
}
