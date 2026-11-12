@props(['pagina', 'etiqueta' => 'Páginas de proyectos'])
@if($pagina->hasPages())
<nav class="d-flex flex-wrap align-items-center justify-content-between gap-3 mt-4" aria-label="{{ $etiqueta }}">
    <p class="small text-body-secondary mb-0">Página {{ $pagina->currentPage() }} de {{ $pagina->lastPage() }}</p>
    <ul class="pagination">
        @if($pagina->onFirstPage())<li class="page-item disabled" aria-disabled="true"><span class="page-link">Anterior</span></li>
        @else<li class="page-item"><a class="page-link" href="{{ $pagina->previousPageUrl() }}" rel="prev">Anterior</a></li>@endif
        @if($pagina->hasMorePages())<li class="page-item"><a class="page-link" href="{{ $pagina->nextPageUrl() }}" rel="next">Siguiente</a></li>
        @else<li class="page-item disabled" aria-disabled="true"><span class="page-link">Siguiente</span></li>@endif
    </ul>
</nav>
@endif
