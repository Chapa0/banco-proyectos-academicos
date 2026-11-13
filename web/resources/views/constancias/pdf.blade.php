@php
    $zona = 'America/Mexico_City';
    $meses = [1 => 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    $fecha = function (?string $valor) use ($zona, $meses) {
        if (! $valor) {
            return 'sin registrar';
        }
        $f = \Carbon\CarbonImmutable::parse($valor)->setTimezone($zona);

        return $f->day.' de '.$meses[$f->month].' de '.$f->year;
    };
    $hoy = $fecha(now()->toIso8601String());
    $esAlumno = $c->tipo === 'candidatura';
    $companeros = collect($c->alumnos);
@endphp
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Constancia {{ $c->folio }}</title>
<style>
    @page { margin: 0; }
    body { margin: 0; font-family: 'DejaVu Sans', sans-serif; color: #183342; font-size: 11pt; line-height: 1.5; }
    .marco { position: absolute; top: 28pt; left: 28pt; right: 28pt; bottom: 28pt; border: 1.5pt solid #245c59; }
    .marco-interior { position: absolute; top: 34pt; left: 34pt; right: 34pt; bottom: 34pt; border: 0.5pt solid #9fbcb9; }
    .contenido { position: absolute; top: 70pt; left: 72pt; right: 72pt; bottom: 70pt; }
    .franja { height: 6pt; background: #245c59; width: 60pt; margin-bottom: 14pt; }
    .institucion { font-size: 9pt; letter-spacing: 2pt; text-transform: uppercase; color: #536670; margin: 0; }
    h1 { font-size: 26pt; margin: 6pt 0 0; color: #245c59; font-weight: bold; }
    .subtitulo { font-size: 12pt; margin: 2pt 0 28pt; color: #536670; }
    .otorga { margin: 0 0 6pt; }
    .nombre { font-size: 20pt; font-weight: bold; margin: 0 0 4pt; color: #183342; }
    .datos-persona { color: #536670; margin: 0 0 22pt; font-size: 10pt; }
    .texto { margin: 0 0 18pt; text-align: justify; }
    .proyecto { font-weight: bold; }
    table.detalle { width: 100%; border-collapse: collapse; margin: 0 0 20pt; font-size: 10pt; }
    table.detalle th { text-align: left; width: 32%; color: #536670; font-weight: normal; padding: 5pt 8pt 5pt 0; border-bottom: 0.5pt solid #d9e0e3; vertical-align: top; }
    table.detalle td { padding: 5pt 0; border-bottom: 0.5pt solid #d9e0e3; vertical-align: top; }
    .pie { position: absolute; left: 72pt; right: 72pt; bottom: 64pt; font-size: 8.5pt; color: #536670; }
    .pie table { width: 100%; border-collapse: collapse; }
    .folio { font-weight: bold; color: #183342; font-size: 10pt; }
    .nota { margin-top: 8pt; border-top: 0.5pt solid #d9e0e3; padding-top: 6pt; }
</style>
</head>
<body>
<div class="marco"></div>
<div class="marco-interior"></div>
<div class="contenido">
    <div class="franja"></div>
    <p class="institucion">Banco de proyectos académicos</p>
    <h1>Constancia de participación</h1>
    <p class="subtitulo">{{ $esAlumno ? 'Participación de alumno en proyecto con empresa' : 'Dirección académica de proyecto con empresa' }}</p>

    <p class="otorga">Se hace constar que</p>
    <p class="nombre">{{ $c->participante->nombre }}</p>
    <p class="datos-persona">
        {{ $esAlumno ? 'Matrícula' : 'Número de empleado' }} {{ $c->participante->identificador }}@if($esAlumno && $c->participante->carrera) · {{ $c->participante->carrera }}@endif
    </p>

    <p class="texto">
        {{ $esAlumno ? 'participó como integrante del equipo de alumnos en el proyecto' : 'participó en la dirección académica del proyecto' }}
        <span class="proyecto">«{{ $c->proyecto->titulo }}»</span>, propuesto por <span class="proyecto">{{ $c->proyecto->empresa }}</span>,
        desde el {{ $fecha($c->periodo->inicio) }} hasta su conclusión el {{ $fecha($c->periodo->fin) }}.
    </p>

    <table class="detalle">
        <tr><th>Empresa</th><td>{{ $c->proyecto->empresa }}</td></tr>
        @if($c->proyecto->modalidad)<tr><th>Modalidad</th><td>{{ $c->proyecto->modalidad }}</td></tr>@endif
        <tr><th>Periodo</th><td>{{ $fecha($c->periodo->inicio) }} al {{ $fecha($c->periodo->fin) }}</td></tr>
        @if(count($c->directores))<tr><th>{{ count($c->directores) === 1 ? 'Dirección académica' : 'Directores académicos' }}</th><td>{{ implode(', ', $c->directores) }}</td></tr>@endif
        @if($companeros->isNotEmpty())<tr><th>{{ $esAlumno ? 'Equipo de alumnos' : 'Alumnos dirigidos' }}</th><td>{{ $companeros->implode(', ') }}</td></tr>@endif
    </table>

    <p class="texto">Se extiende la presente a solicitud de la persona interesada el {{ $hoy }}, para los fines que a su derecho convengan.</p>

</div>
<div class="pie">
        <table><tr>
            <td>Folio <span class="folio">{{ $c->folio }}</span></td>
            <td style="text-align: right;">Emitida el {{ $hoy }}</td>
        </tr></table>
        <p class="nota">Documento generado por el sistema a partir del registro de asignaciones y del cierre del proyecto. No sustituye una constancia firmada por la institución.</p>
</div>
</body>
</html>
