<?php

namespace App\Services;

use Illuminate\Database\QueryException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Throwable;

/**
 * D-11: PDF de evidencias y currículum. El contenido se guarda en el disco privado «local»
 * (fuera de public) con nombre aleatorio; PostgreSQL registra metadatos y decide permisos (D-10).
 */
class DocumentoService
{
    private const DISCO = 'local';

    public function subir(int $actor, string $tipo, ?int $habilidad, UploadedFile $archivo): int
    {
        $ruta = 'documentos/'.Str::uuid()->toString().'.pdf';
        $contenido = (string) file_get_contents($archivo->getRealPath());
        if (! Storage::disk(self::DISCO)->put($ruta, $contenido)) {
            Log::error('No fue posible almacenar un documento del perfil.');
            throw ValidationException::withMessages(['archivo' => 'No fue posible guardar el archivo. Intenta de nuevo más tarde.']);
        }
        try {
            return (int) DB::transaction(fn () => DB::selectOne('SELECT banco.web_registrar_documento(?,?,?,?,?,?,?) AS id', [
                $actor, $tipo, $habilidad, $this->nombreSeguro($archivo->getClientOriginalName()),
                $ruta, strlen($contenido), hash('sha256', $contenido),
            ])->id, 1);
        } catch (Throwable $error) {
            // Sin registro en la base no debe quedar un archivo huérfano.
            Storage::disk(self::DISCO)->delete($ruta);
            $estado = $error instanceof QueryException ? ($error->errorInfo[0] ?? null) : null;
            abort_if($estado === '42501', 403);
            if ($estado === '23514') {
                $mensaje = str_contains($error->getMessage(), 'Máximo tres')
                    ? 'Ya tienes tres archivos en esta habilidad. Quita uno antes de subir otro.'
                    : 'Esa habilidad ya no está en tu perfil. Guarda tu perfil con la habilidad seleccionada y vuelve a intentarlo.';
                throw ValidationException::withMessages(['archivo' => $mensaje]);
            }
            Log::error('No se registró un documento del perfil.', ['sqlstate' => $estado]);
            throw ValidationException::withMessages(['archivo' => 'No fue posible guardar el archivo. Intenta de nuevo más tarde.']);
        }
    }

    public function retirar(int $actor, int $documento): void
    {
        try {
            DB::transaction(fn () => DB::select('SELECT banco.web_retirar_documento(?,?)', [$actor, $documento]), 1);
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? null;
            abort_if($estado === '23503', 404);
            abort_if($estado === '42501', 403);
            Log::error('No se retiró un documento del perfil.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
    }

    /** @return array<object> documentos vigentes del titular que el actor puede consultar */
    public function delPerfil(int $actor, int $titular): array
    {
        $datos = $this->leer('SELECT banco.web_documentos_perfil(?,?) AS resultado', [$actor, $titular]);

        return is_array($datos) ? $datos : [];
    }

    /**
     * Documentos de varios perfiles ya autorizados para el actor (los que una consulta previa devolvió).
     *
     * @param  iterable<object|null>  $perfiles  objetos de consultar_perfil con usuario_id
     * @return array<int, array<object>>
     */
    public function mapa(int $actor, iterable $perfiles): array
    {
        $salida = [];
        foreach ($perfiles as $perfil) {
            if (isset($perfil->usuario_id) && ! isset($salida[(int) $perfil->usuario_id])) {
                $salida[(int) $perfil->usuario_id] = $this->delPerfil($actor, (int) $perfil->usuario_id);
            }
        }

        return $salida;
    }

    /** Metadatos y ruta privada; 404 si no existe o el actor no puede verlo. */
    public function abrir(int $actor, int $documento): object
    {
        $datos = $this->leer('SELECT banco.web_abrir_documento(?,?) AS resultado', [$actor, $documento]);
        abort_unless(is_object($datos) && Storage::disk(self::DISCO)->exists($datos->ruta), 404);

        return $datos;
    }

    public function ruta(object $documento): string
    {
        return Storage::disk(self::DISCO)->path($documento->ruta);
    }

    private function leer(string $sql, array $parametros): object|array|null
    {
        try {
            $resultado = DB::selectOne($sql, $parametros)?->resultado;

            return $resultado === null ? null : json_decode($resultado, false, 512, JSON_THROW_ON_ERROR);
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? null;
            abort_if(in_array($estado, ['23503', '23514'], true), 404);
            abort_if($estado === '42501', 403);
            Log::error('No fue posible consultar documentos del perfil.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
    }

    /** Nombre visible sin rutas ni caracteres de control; siempre termina en .pdf. */
    private function nombreSeguro(string $nombre): string
    {
        $base = preg_replace('/[\x00-\x1F\x7F\/\\\\:*?"<>|]+/u', ' ', pathinfo($nombre, PATHINFO_FILENAME)) ?? '';
        $base = trim(preg_replace('/\s+/u', ' ', $base) ?? '');

        return Str::limit($base === '' ? 'documento' : $base, 200, '').'.pdf';
    }
}
