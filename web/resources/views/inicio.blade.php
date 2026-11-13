@extends('layouts.app')

@section('content')
    {{-- RD-01: portada pública. Contenido fijo: no consulta datos de la base. --}}
    <section class="container hero" aria-labelledby="portada-titulo">
        <div>
            <span class="hero-eyebrow"><i class="bi bi-stars" aria-hidden="true"></i>Vinculación escuela–empresa</span>
            <h1 id="portada-titulo">Proyectos reales para <span>aprender haciendo</span></h1>
            <p class="hero-lead">Las empresas proponen sus necesidades tecnológicas, los alumnos se postulan según sus habilidades y los profesores dirigen el trabajo. Todo en un solo lugar, con la coordinación acompañando cada paso.</p>
            <div class="hero-actions">
                <a class="btn btn-primary px-4" href="{{ route('login') }}">Iniciar sesión <i class="bi bi-arrow-right ms-2" aria-hidden="true"></i></a>
                <a class="btn btn-outline-secondary px-4" href="#como-funciona">Conoce el proceso</a>
            </div>
        </div>
        <div class="hero-visual" aria-hidden="true">
            <div class="hero-card">
                <p class="hero-card-title">Control de inventario de insumos</p>
                <p class="hero-card-sub"><span class="hero-chip">LE</span>Panadería La Espiga · Presencial</p>
                <p class="hero-card-sub mb-0"><strong class="text-body-emphasis">Cumples 3 de 3</strong>&nbsp;habilidades solicitadas</p>
                <div class="hero-bar"><span></span></div>
            </div>
            <div class="hero-card">
                <p class="hero-card-title">Candidatura · Sistema de pedidos</p>
                <p class="hero-card-sub mb-0"><span class="status-badge status-active"><i class="bi bi-check-circle-fill"></i>Aprobada</span>Participando en el proyecto</p>
            </div>
        </div>
    </section>

    <div class="landing-band">
        <section id="como-funciona" class="container landing-section" aria-labelledby="proceso-titulo">
            <h2 id="proceso-titulo">Cómo funciona</h2>
            <p class="landing-sub">De una necesidad de la empresa a una oportunidad de aprendizaje.</p>
            <ol class="feature-grid">
                <li class="feature-card">
                    <div class="feature-icon" aria-hidden="true"><i class="bi bi-lightbulb"></i></div>
                    <span class="feature-step">Paso 1</span>
                    <h3>Proponer</h3>
                    <p>La empresa describe su proyecto y la institución revisa sus objetivos, alcance y cupo antes de publicarlo.</p>
                </li>
                <li class="feature-card">
                    <div class="feature-icon" aria-hidden="true"><i class="bi bi-person-raised-hand"></i></div>
                    <span class="feature-step">Paso 2</span>
                    <h3>Participar</h3>
                    <p>Los alumnos presentan su candidatura y los profesores solicitan la dirección de los proyectos de su interés.</p>
                </li>
                <li class="feature-card">
                    <div class="feature-icon" aria-hidden="true"><i class="bi bi-rocket-takeoff"></i></div>
                    <span class="feature-step">Paso 3</span>
                    <h3>Desarrollar</h3>
                    <p>La empresa evalúa a los candidatos. La administración autoriza las asignaciones y confirma el inicio con alumnos y director.</p>
                </li>
            </ol>
        </section>
    </div>

    <section id="participantes" class="container landing-section" aria-labelledby="participantes-titulo">
        <h2 id="participantes-titulo">Un trabajo compartido</h2>
        <p class="landing-sub">Cada cuenta ve solo lo que necesita.</p>
        <ul class="feature-grid is-four">
            <li class="feature-card">
                <div class="feature-icon" aria-hidden="true"><i class="bi bi-buildings"></i></div>
                <h3>Empresas</h3>
                <p>Plantean necesidades, proponen proyectos y evalúan a los alumnos interesados.</p>
            </li>
            <li class="feature-card">
                <div class="feature-icon" aria-hidden="true"><i class="bi bi-mortarboard"></i></div>
                <h3>Alumnos</h3>
                <p>Comparten sus habilidades, reciben recomendaciones y se postulan para ponerlas en práctica.</p>
            </li>
            <li class="feature-card">
                <div class="feature-icon" aria-hidden="true"><i class="bi bi-person-workspace"></i></div>
                <h3>Profesores</h3>
                <p>Aportan su experiencia y acompañan el desarrollo de los proyectos como directores.</p>
            </li>
            <li class="feature-card">
                <div class="feature-icon" aria-hidden="true"><i class="bi bi-clipboard-data"></i></div>
                <h3>Administración</h3>
                <p>Revisa publicaciones, autoriza participantes y consulta reportes con gráficas.</p>
            </li>
        </ul>
    </section>
@endsection
