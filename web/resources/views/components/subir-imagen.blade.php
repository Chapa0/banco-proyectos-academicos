@props(['id', 'titulo', 'descripcion', 'imagen' => null, 'nombre' => '', 'logo' => false, 'accionGuardar', 'accionQuitar', 'confirmar'])
{{-- UX-08: subir, reemplazar o quitar la foto de perfil o el logo de empresa. --}}
<section class="surface mt-4" id="{{ $id }}" aria-labelledby="{{ $id }}-titulo">
    <h2 class="section-heading" id="{{ $id }}-titulo">{{ $titulo }}</h2>
    <p class="field-hint">{{ $descripcion }}</p>
    <div class="image-upload">
        <x-avatar :imagen="$imagen" :nombre="$nombre" tamano="xl" :logo="$logo" :alt="$imagen ? $titulo.' actual' : null" />
        <div class="image-upload-actions">
            <form method="POST" action="{{ $accionGuardar }}" enctype="multipart/form-data" data-submit-label="Subiendo imagen…" data-sin-aviso-salida>
                @csrf
                <div class="label-row">
                    <label class="form-label" for="{{ $id }}-archivo">{{ $imagen ? 'Reemplazar imagen' : 'Elegir imagen' }}</label>
                    <x-info :tema="$titulo" texto="JPG, PNG o WebP de hasta 4 MB. Se recorta en cuadrado y se guarda en tamaño reducido, sin datos de ubicación ni de la cámara." />
                </div>
                <div class="document-upload-row">
                    <input class="form-control @error('imagen') is-invalid @enderror" id="{{ $id }}-archivo" name="imagen" type="file" accept="image/jpeg,image/png,image/webp" required @error('imagen') aria-invalid="true" aria-describedby="{{ $id }}-error" @enderror>
                    <button class="btn btn-primary" type="submit">{{ $imagen ? 'Reemplazar' : 'Subir' }}</button>
                </div>
                @error('imagen')<div class="invalid-feedback d-block" id="{{ $id }}-error">{{ $message }}</div>@enderror
            </form>
            @if($imagen)
                <form method="POST" action="{{ $accionQuitar }}" data-confirm="{{ $confirmar }}" class="mt-2">
                    @csrf @method('DELETE')
                    <button class="btn btn-link text-danger px-0" type="submit">Quitar imagen</button>
                </form>
            @endif
        </div>
    </div>
</section>
