<?php

namespace App\Http\Controllers;

use App\Http\Requests\Consultas\FiltrarReporteRequest;
use App\Services\ConsultaService;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Log;
use Illuminate\View\View;
use Symfony\Component\HttpFoundation\StreamedResponse;

class ReporteController extends Controller
{
    public function __construct(private readonly ConsultaService $consultas) {}

    public function index(FiltrarReporteRequest $request, string $tipo = 'proyectos'): View
    {
        Gate::authorize('consultar-reportes');
        $filtros = $request->validated();
        $datos = $this->consultas->reporte((int) $request->user()->getAuthIdentifier(), $tipo, $filtros);
        $estados = $this->consultas->estadosReporte($tipo);

        return view('reportes.index', [
            'tipo' => $tipo, 'tipos' => ConsultaService::TIPOS_REPORTE, 'filas' => $datos->pagina,
            'resumen' => $datos->resumen, 'opciones' => $datos->opciones, 'filtros' => $filtros,
            'estados' => $estados, 'campos' => array_merge($estados === [] ? [] : ['estado'], ConsultaService::FILTROS_REPORTE[$tipo]),
            'columnas' => ConsultaService::COLUMNAS_REPORTE[$tipo],
            'panorama' => $this->consultas->panorama((int) $request->user()->getAuthIdentifier()),
        ]);
    }

    /** CSV en UTF-8 con BOM para que Excel respete los acentos; conserva los filtros de la consulta. */
    public function exportar(FiltrarReporteRequest $request, string $tipo): StreamedResponse
    {
        Gate::authorize('consultar-reportes');
        $actor = (int) $request->user()->getAuthIdentifier();
        $datos = $this->consultas->exportarReporte($actor, $tipo, $request->validated());
        Log::info('Reporte exportado.', ['actor' => $actor, 'tipo' => $tipo, 'filas' => count($datos['filas'])]);
        $archivo = 'reporte-'.str_replace('_', '-', $tipo).'-'.now('America/Mexico_City')->format('Y-m-d').'.csv';

        return response()->streamDownload(function () use ($datos) {
            $salida = fopen('php://output', 'wb');
            fwrite($salida, "\xEF\xBB\xBF");
            fputcsv($salida, array_values($datos['columnas']), ',', '"', '');
            foreach ($datos['filas'] as $fila) {
                fputcsv($salida, array_map(self::celdaSegura(...), $fila), ',', '"', '');
            }
            fclose($salida);
        }, $archivo, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Cache-Control' => 'private, no-store',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }

    /** Evita que una hoja de cálculo interprete como fórmula un texto escrito por un usuario. */
    public static function celdaSegura(string $valor): string
    {
        return preg_match('/\A[=+\-@\t\r]/', $valor) === 1 ? "'".$valor : $valor;
    }
}
