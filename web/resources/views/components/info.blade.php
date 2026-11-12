@props(['texto', 'tema' => null])
{{-- Ayuda ampliada junto a una etiqueta: se muestra al pasar el cursor, al enfocar con teclado o al tocar.
     Sin JavaScript, el texto sigue disponible como title y para lectores de pantalla. --}}
<button type="button" class="info-tip" data-info-tip title="{{ $texto }}" aria-label="Más información{{ $tema ? ' sobre '.mb_strtolower($tema) : '' }}: {{ $texto }}">
    <span aria-hidden="true">i</span>
</button>
