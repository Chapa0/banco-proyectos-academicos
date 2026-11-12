@extends('layouts.app')
@section('title', 'Revisión de proyectos · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <header class="page-header"><div><h1 class="page-title">Revisión de proyectos</h1><p class="page-description">Revisa los envíos de las empresas y consulta sus resoluciones.</p></div></header>
    <x-errores />
    @include('proyectos._lista', ['administracion' => true])
</section>
@endsection
