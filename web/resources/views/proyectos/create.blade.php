@extends('layouts.app')
@section('title', 'Crear proyecto · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <a class="back-link" href="{{ route('proyectos.index') }}"><i class="bi bi-arrow-left me-2" aria-hidden="true"></i>Volver a mis proyectos</a>
    <header class="page-header"><div><h1 class="page-title">Crear proyecto</h1><p class="page-description">Guarda primero un borrador. Podrás revisarlo antes de enviarlo al administrador.</p></div></header>
    <div class="form-layout"><x-errores />
        <form class="surface" method="POST" action="{{ route('proyectos.store') }}" data-submit-label="Guardando…">
            @csrf
            @include('proyectos._campos')
            <div class="form-actions"><button type="submit" class="btn btn-primary">Guardar borrador</button><a class="btn btn-outline-secondary" href="{{ route('proyectos.index') }}">Cancelar</a></div>
        </form>
    </div>
</section>
@endsection
