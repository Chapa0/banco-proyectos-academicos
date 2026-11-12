@extends('layouts.app')
@section('title', 'Mis proyectos · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <header class="page-header"><div><h1 class="page-title">Mis proyectos</h1><p class="page-description">Consulta tus borradores, envíos y resoluciones.</p></div><a class="btn btn-primary" href="{{ route('proyectos.create') }}">Crear proyecto</a></header>
    <x-errores />
    @include('proyectos._lista', ['administracion' => false])
</section>
@endsection
