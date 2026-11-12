<?php

namespace App\Http\Controllers;

use Illuminate\Contracts\View\View;

final class InicioController extends Controller
{
    public function __invoke(): View
    {
        return view('inicio');
    }
}
