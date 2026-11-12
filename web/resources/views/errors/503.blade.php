@extends('layouts.estado')
@section('title', 'Servicio no disponible')
@section('heading', 'No pudimos completar la operación')
@section('message', 'El servicio no está disponible en este momento. Inténtalo más tarde.')
@section('action')
<a class="btn btn-outline-secondary" href="{{ route('inicio') }}">Volver al inicio</a>
@endsection
