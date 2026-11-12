@props(['documento'])
{{-- Descarga de un PDF autorizado (D-11): siempre como archivo adjunto. --}}
<a {{ $attributes->class(['document-link']) }} href="{{ route('documentos.show', $documento->id) }}" download>
    <span class="document-icon" aria-hidden="true">PDF</span>
    <span class="document-name">{{ $documento->nombre_original }}</span>
    <span class="document-meta">{{ \Illuminate\Support\Number::fileSize($documento->tamano_bytes, maxPrecision: 1) }}<span class="visually-hidden">, descargar</span></span>
</a>
