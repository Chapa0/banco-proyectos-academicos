<?php

namespace App\Services;

use GdImage;
use Illuminate\Database\QueryException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Throwable;

/**
 * UX-08: foto de perfil y logo de empresa. Cada imagen se vuelve a codificar con GD como WebP cuadrado
 * de 320 px: así se descartan metadatos (ubicación, cámara) y cualquier contenido que no sea imagen.
 * Se guarda en el disco privado; PostgreSQL (029) registra metadatos y decide quién la ve.
 */
class ImagenService
{
    private const DISCO = 'local';

    public const LADO = 320;

    public function subir(int $actor, string $tipo, UploadedFile $archivo): int
    {
        $contenido = $this->normalizar($archivo, $tipo);
        $ruta = 'imagenes/'.Str::uuid()->toString().'.webp';
        if (! Storage::disk(self::DISCO)->put($ruta, $contenido)) {
            Log::error('No fue posible almacenar una imagen.');
            throw ValidationException::withMessages(['imagen' => 'No fue posible guardar la imagen. Intenta de nuevo más tarde.']);
        }
        try {
            return (int) DB::transaction(fn () => DB::selectOne('SELECT banco.web_registrar_imagen(?,?,?,?,?) AS id', [
                $actor, $tipo, $ruta, strlen($contenido), hash('sha256', $contenido),
            ])->id, 1);
        } catch (Throwable $error) {
            Storage::disk(self::DISCO)->delete($ruta);
            $estado = $error instanceof QueryException ? ($error->errorInfo[0] ?? null) : null;
            abort_if(in_array($estado, ['42501', '23503'], true), 403);
            Log::error('No se registró una imagen.', ['sqlstate' => $estado]);
            throw ValidationException::withMessages(['imagen' => 'No fue posible guardar la imagen. Intenta de nuevo más tarde.']);
        }
    }

    public function retirar(int $actor, string $tipo): void
    {
        try {
            DB::transaction(fn () => DB::select('SELECT banco.web_retirar_imagen(?,?)', [$actor, $tipo]), 1);
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? null;
            abort_if($estado === '23503', 404);
            abort_if($estado === '42501', 403);
            Log::error('No se retiró una imagen.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
    }

    /**
     * Ids de imágenes visibles para el actor. Es una ayuda visual: si falla, se muestran iniciales.
     *
     * @return object{fotos: array<int,int>, logos: array<int,int>, logos_proyecto: array<int,int>}
     */
    public function mapa(int $actor, array $usuarios = [], array $empresas = [], array $proyectos = []): object
    {
        $vacio = (object) ['fotos' => [], 'logos' => [], 'logos_proyecto' => []];
        $lista = fn (array $ids) => '{'.implode(',', array_slice(array_unique(array_map('intval', array_filter($ids, 'is_numeric'))), 0, 100)).'}';
        if ($usuarios === [] && $empresas === [] && $proyectos === []) {
            return $vacio;
        }
        try {
            $resultado = DB::selectOne('SELECT banco.web_imagenes(?,CAST(? AS bigint[]),CAST(? AS bigint[]),CAST(? AS bigint[])) AS resultado', [
                $actor, $lista($usuarios), $lista($empresas), $lista($proyectos),
            ])?->resultado;
            $datos = json_decode($resultado ?? '{}', true, 512, JSON_THROW_ON_ERROR);
        } catch (Throwable $error) {
            Log::warning('No fue posible consultar las imágenes.', ['error' => $error::class]);

            return $vacio;
        }
        $enteros = fn ($m) => collect(is_array($m) ? $m : [])->mapWithKeys(fn ($v, $k) => [(int) $k => (int) $v])->all();

        return (object) ['fotos' => $enteros($datos['fotos'] ?? []), 'logos' => $enteros($datos['logos'] ?? []),
            'logos_proyecto' => $enteros($datos['logos_proyecto'] ?? [])];
    }

    /** @return array{0:string,1:string} [ruta absoluta, etiqueta para caché] */
    public function abrir(int $actor, int $imagen): array
    {
        try {
            $datos = json_decode((string) DB::selectOne('SELECT banco.web_abrir_imagen(?,?) AS resultado', [$actor, $imagen])?->resultado, false, 512, JSON_THROW_ON_ERROR);
        } catch (QueryException $error) {
            $estado = $error->errorInfo[0] ?? null;
            abort_if(in_array($estado, ['23503', '42501', '23514'], true), 404);
            Log::error('No fue posible abrir una imagen.', ['sqlstate' => $estado]);
            abort(503, 'El servicio no está disponible en este momento.');
        }
        abort_unless(Storage::disk(self::DISCO)->exists($datos->ruta), 404);

        return [Storage::disk(self::DISCO)->path($datos->ruta), $datos->sha256];
    }

    /** Recorta (foto) o encaja con fondo transparente (logo) en un cuadrado y devuelve WebP. */
    private function normalizar(UploadedFile $archivo, string $tipo): string
    {
        $origen = @imagecreatefromstring((string) file_get_contents($archivo->getRealPath()));
        if (! $origen instanceof GdImage) {
            throw ValidationException::withMessages(['imagen' => 'No pudimos leer la imagen. Usa un archivo JPG, PNG o WebP.']);
        }
        $ancho = imagesx($origen);
        $alto = imagesy($origen);
        $lado = self::LADO;
        $destino = imagecreatetruecolor($lado, $lado);
        imagealphablending($destino, false);
        imagesavealpha($destino, true);
        imagefill($destino, 0, 0, imagecolorallocatealpha($destino, 0, 0, 0, 127));
        imagealphablending($destino, true);
        if ($tipo === 'foto') {
            // Recorte centrado del cuadrado más grande posible.
            $corte = min($ancho, $alto);
            imagecopyresampled($destino, $origen, 0, 0, intdiv($ancho - $corte, 2), intdiv($alto - $corte, 2), $lado, $lado, $corte, $corte);
        } else {
            // El logo se ve completo, con un pequeño margen.
            $escala = min(($lado - 24) / $ancho, ($lado - 24) / $alto);
            $w = max(1, (int) round($ancho * $escala));
            $h = max(1, (int) round($alto * $escala));
            imagecopyresampled($destino, $origen, intdiv($lado - $w, 2), intdiv($lado - $h, 2), 0, 0, $w, $h, $ancho, $alto);
        }
        ob_start();
        imagewebp($destino, null, 85);

        return (string) ob_get_clean();
    }
}
