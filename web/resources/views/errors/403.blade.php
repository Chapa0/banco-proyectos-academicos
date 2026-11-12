@extends('layouts.estado')
@section('title', 'Acceso restringido')
@section('heading', 'No tienes acceso a esta sección')
@section('message', 'Tu cuenta no tiene permiso para realizar esta acción. Puedes volver a tu espacio.')
@section('action')
<a class="btn btn-primary" href="{{ route('panel') }}">Volver a mi espacio</a>
@endsection
