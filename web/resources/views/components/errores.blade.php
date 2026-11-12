@if($errors->any())
<div class="alert alert-danger mb-4" id="errores-formulario" role="alert" tabindex="-1">
    <p class="fw-semibold mb-2">Revisa los datos antes de continuar.</p>
    <ul class="mb-0">@foreach($errors->all() as $mensaje)<li>{{ $mensaje }}</li>@endforeach</ul>
</div>
@endif
