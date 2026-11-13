<?php

namespace App\Support;

use Illuminate\Http\Request;
use Illuminate\Routing\Route as RutaLaravel;
use Illuminate\Support\Facades\Route;
use Throwable;

/**
 * NAV-01: regreso al lugar de origen.
 *
 * Los enlaces que llevan a otra página añaden la página actual en ?volver=. El enlace
 * «Volver» de la página destino la usa si es una dirección interna de una ruta conocida;
 * si no la hay o no es válida, regresa a la lista de su sección como antes. Como el origen
 * conserva su propia consulta, también se recuperan filtros, página y regresos anteriores.
 */
final class Regreso
{
    public const PARAMETRO = 'volver';

    private const LARGO_MAXIMO = 1500;

    /** Texto del enlace según la ruta de origen. */
    private const ETIQUETAS = [
        'panel' => 'Volver a mi espacio',
        'catalogo.index' => 'Volver al catálogo',
        'catalogo.show' => 'Volver al proyecto',
        'participacion.create' => 'Volver a la solicitud',
        'participacion.index' => ['candidatura' => 'Volver a candidaturas', 'direccion' => 'Volver a solicitudes de dirección'],
        'participacion.show' => ['candidatura' => 'Volver a la candidatura', 'direccion' => 'Volver a la solicitud de dirección'],
        'seguimiento.index' => 'Volver al seguimiento',
        'seguimiento.show' => 'Volver al proyecto',
        'proyectos.index' => 'Volver a mis proyectos',
        'proyectos.show' => 'Volver al proyecto',
        'revision.index' => 'Volver a revisión de proyectos',
        'revision.show' => 'Volver a la revisión del proyecto',
        'avisos.index' => 'Volver a mis avisos',
        'avisos.show' => 'Volver al aviso',
        'reportes.index' => 'Volver a reportes',
        'cuentas.index' => 'Volver a cuentas',
        'cuentas.edit' => 'Volver a la cuenta',
        'habilidades.index' => 'Volver al catálogo de habilidades',
        'perfil.edit' => 'Volver a mi perfil',
        'empresa.edit' => 'Volver a datos de empresa',
    ];

    /** Añade a $url la página actual como origen del regreso. */
    public static function enlace(string $url, ?Request $peticion = null): string
    {
        $origen = self::origen($peticion ?? request());
        [$base, $fragmento] = array_pad(explode('#', $url, 2), 2, null);
        $base .= (str_contains($base, '?') ? '&' : '?').self::PARAMETRO.'='.rawurlencode($origen);

        return $fragmento === null ? $base : $base.'#'.$fragmento;
    }

    /**
     * Destino y texto del enlace «Volver».
     *
     * @return array{url: string, etiqueta: string}
     */
    public static function destino(string $defecto, string $etiqueta, ?Request $peticion = null): array
    {
        $peticion ??= request();
        $valor = self::valorRecibido($peticion);
        $ruta = $valor === null ? null : self::rutaConocida($valor);
        if ($ruta === null) {
            return ['url' => $defecto, 'etiqueta' => $etiqueta];
        }

        return ['url' => url($valor), 'etiqueta' => self::etiqueta($ruta)];
    }

    /**
     * El origen llega en la consulta. Tras enviar un formulario, la redirección vuelve a la
     * misma página sin consulta; entonces se recupera de la página anterior si era esta misma.
     */
    private static function valorRecibido(Request $peticion): ?string
    {
        $valor = $peticion->query(self::PARAMETRO);
        if (is_string($valor)) {
            return $valor;
        }
        $anterior = $peticion->hasSession() ? $peticion->session()->previousUrl() : null;
        if (! is_string($anterior) || parse_url($anterior, PHP_URL_PATH) !== '/'.ltrim($peticion->path(), '/')) {
            return null;
        }
        parse_str((string) parse_url($anterior, PHP_URL_QUERY), $consulta);

        return is_string($consulta[self::PARAMETRO] ?? null) ? $consulta[self::PARAMETRO] : null;
    }

    /** Dirección relativa de la página actual; si es muy larga se descarta la cadena de regresos. */
    private static function origen(Request $peticion): string
    {
        $ruta = '/'.ltrim($peticion->path(), '/');
        $consulta = $peticion->query();
        $completo = $consulta ? $ruta.'?'.http_build_query($consulta) : $ruta;
        if (strlen($completo) <= self::LARGO_MAXIMO) {
            return $completo;
        }
        unset($consulta[self::PARAMETRO]);
        $reducido = $consulta ? $ruta.'?'.http_build_query($consulta) : $ruta;

        return strlen($reducido) <= self::LARGO_MAXIMO ? $reducido : $ruta;
    }

    /** Solo direcciones relativas del propio sistema que correspondan a una ruta con texto conocido. */
    private static function rutaConocida(string $valor): ?RutaLaravel
    {
        if ($valor === '' || strlen($valor) > self::LARGO_MAXIMO || $valor[0] !== '/' || str_starts_with($valor, '//')
            || preg_match('/[\\\\\x00-\x1F\x7F]/', $valor)) {
            return null;
        }
        try {
            $ruta = Route::getRoutes()->match(Request::create($valor, 'GET'));
        } catch (Throwable) {
            return null;
        }

        return isset(self::ETIQUETAS[$ruta->getName() ?? '']) ? $ruta : null;
    }

    private static function etiqueta(RutaLaravel $ruta): string
    {
        $etiqueta = self::ETIQUETAS[$ruta->getName()];
        if (is_array($etiqueta)) {
            return $etiqueta[$ruta->parameter('tipo')] ?? 'Volver';
        }

        return $etiqueta;
    }
}
