@extends('layouts.estado')
@section('title', 'Sesión vencida')
@section('heading', 'Tu sesión ha vencido')
@section('message', 'Vuelve a iniciar sesión antes de intentar la operación de nuevo.')
@section('action')
<a class="btn btn-primary" href="{{ route('login') }}">Iniciar sesión</a>
@endsection
