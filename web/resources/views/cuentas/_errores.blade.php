@if ($errors->any())
    <div class="alert alert-danger" role="alert" id="errores-formulario" tabindex="-1">
        <p class="fw-semibold mb-2">Revisa los datos antes de continuar.</p>
        <ul class="mb-0">
            @foreach ($errors->all() as $error)
                <li>{{ $error }}</li>
            @endforeach
        </ul>
    </div>
@endif
