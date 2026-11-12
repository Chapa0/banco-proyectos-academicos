<?php

namespace App\Http\Controllers;

abstract class Controller
{
    protected function identificadorRuta(string $valor): int
    {
        $identificador = filter_var($valor, FILTER_VALIDATE_INT);
        abort_if($identificador === false || $identificador === 0, 404);

        return $identificador;
    }
}
