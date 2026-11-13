{{-- UX-09: panorama global (sin filtros). Cada barra abre el reporte filtrado por ese estado. --}}
@php
    $filas = function (object $conteos, array $estados, string $tipo) {
        $salida = [];
        foreach ($estados as $codigo => $nombre) {
            $salida[] = ['etiqueta' => $nombre, 'valor' => (int) ($conteos->{$codigo} ?? 0), 'url' => route('reportes.index', [$tipo, 'estado' => $codigo])];
        }

        return $salida;
    };
@endphp
<section class="report-overview" aria-labelledby="panorama-titulo">
    <div class="report-overview-header">
        <h2 class="section-heading mb-1" id="panorama-titulo">Panorama general</h2>
        <p class="field-hint mb-0">Totales de todo el sistema, sin filtros. Pasa el cursor por una barra para ver su porcentaje; al elegir una categoría se abre el reporte filtrado.</p>
    </div>
    <div class="chart-grid">
        <x-grafica-barras id="graf-proyectos" titulo="Proyectos por estado" :unidad="['proyecto', 'proyectos']" :filas="$filas($panorama->proyectos, \App\Services\PublicacionService::ESTADOS, 'proyectos')" />
        <x-grafica-barras id="graf-candidaturas" titulo="Candidaturas por estado" :unidad="['candidatura', 'candidaturas']" :filas="$filas($panorama->candidaturas, \App\Services\ParticipacionService::ESTADOS_CANDIDATURA, 'candidaturas')" />
        <x-grafica-barras id="graf-direcciones" titulo="Solicitudes de dirección por estado" :unidad="['solicitud', 'solicitudes']" :filas="$filas($panorama->direcciones, \App\Services\ParticipacionService::ESTADOS_DIRECCION, 'direcciones')" />
        <x-medidores-carga :carga="$panorama->carga" :profesores="(int) $panorama->profesores" />
    </div>
</section>
