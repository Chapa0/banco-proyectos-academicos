<?php

namespace App\Services;

use Dompdf\Dompdf;
use Dompdf\Options;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Constancia de participación en PDF (UX-07). Los datos y el permiso vienen de banco.web_constancia (028):
 * solo el titular o la administración, y solo si la participación concluyó con el cierre del proyecto.
 */
class ConstanciaService
{
    public function datos(int $actor, string $tipo, int $solicitud): object
    {
        try {
            $resultado = DB::selectOne('SELECT banco.web_constancia(?,?,?) AS resultado', [$actor, $tipo, $solicitud])?->resultado;
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? (string) $error->getCode();
            // Sin permiso o sin participación concluida se responde igual que si no existiera.
            abort_if(in_array($estado, ['23503', '23514', '42501'], true), 404);
            Log::error('No fue posible preparar la constancia.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
        abort_if($resultado === null, 404);

        return json_decode($resultado, false, 512, JSON_THROW_ON_ERROR);
    }

    /** PDF carta vertical a partir de la vista Blade; sin recursos remotos ni PHP embebido. */
    public function pdf(object $constancia): string
    {
        $opciones = new Options;
        $opciones->setIsRemoteEnabled(false);
        $opciones->setIsPhpEnabled(false);
        $opciones->setIsJavascriptEnabled(false);
        $opciones->setDefaultFont('DejaVu Sans');
        $opciones->setChroot(resource_path('views/constancias'));
        // `artisan serve` no transmite TEMP/TMP al servidor: sin carpeta propia, dompdf no puede crear
        // el subconjunto de fuentes y el PDF falla en una instalación nueva.
        $opciones->setTempDir(storage_path('framework/cache'));
        $dompdf = new Dompdf($opciones);
        $dompdf->loadHtml(view('constancias.pdf', ['c' => $constancia])->render(), 'UTF-8');
        $dompdf->setPaper('letter', 'portrait');
        $dompdf->addInfo('Title', 'Constancia de participación '.$constancia->folio);
        $dompdf->addInfo('Creator', 'Banco de proyectos académicos');
        $dompdf->render();

        return $dompdf->output();
    }
}
