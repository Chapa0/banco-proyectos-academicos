@extends('layouts.estado')
@section('title', 'Página no encontrada')
@section('heading', 'No encontramos esta página')
@section('message', 'Comprueba la dirección o vuelve al inicio para continuar.')
@section('action')
<a class="btn btn-primary" href="{{ route('inicio') }}">Volver al inicio</a>
@endsection
