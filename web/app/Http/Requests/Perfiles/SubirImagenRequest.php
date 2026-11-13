<?php

namespace App\Http\Requests\Perfiles;

use Illuminate\Foundation\Http\FormRequest;

class SubirImagenRequest extends FormRequest
{
    public function authorize(): bool
    {
        // El Gate de la ruta y la base deciden; aquí solo se valida el archivo.
        return true;
    }

    public function rules(): array
    {
        return [
            'imagen' => ['required', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'mimetypes:image/jpeg,image/png,image/webp',
                'max:4096', 'dimensions:min_width=64,min_height=64,max_width=6000,max_height=6000'],
        ];
    }

    public function messages(): array
    {
        return [
            'imagen.required' => 'Elige una imagen.',
            'imagen.image' => 'El archivo debe ser una imagen.',
            'imagen.mimes' => 'Usa una imagen JPG, PNG o WebP.',
            'imagen.mimetypes' => 'Usa una imagen JPG, PNG o WebP.',
            'imagen.max' => 'La imagen no debe pesar más de 4 MB.',
            'imagen.dimensions' => 'La imagen debe medir entre 64 y 6000 píxeles por lado.',
            'imagen.uploaded' => 'No se pudo subir la imagen. Revisa que no pese más de 4 MB.',
        ];
    }
}
