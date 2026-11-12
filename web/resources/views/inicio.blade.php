@extends('layouts.app')

@section('content')
    <section class="intro-section">
        <div class="container">
            <div class="row">
                <div class="col-lg-9">
                    <h1>Banco de proyectos académicos</h1>
                    <p class="intro-text mt-4 mb-4">
                        Un espacio para vincular las necesidades tecnológicas de las empresas
                        con el talento de alumnos y profesores de Sistemas Computacionales.
                    </p>
                    <a class="btn btn-primary px-4 py-3" href="#como-funciona">Conoce el proceso</a>
                </div>
            </div>
        </div>
    </section>

    <section id="como-funciona" class="content-section" aria-labelledby="proceso-titulo">
        <div class="container">
            <h2 id="proceso-titulo">Cómo funciona</h2>
            <p class="section-description mt-3">De una necesidad de la empresa a una oportunidad de aprendizaje.</p>

            <ol class="row g-4 list-unstyled mt-4 mb-0">
                <li class="col-md-4">
                    <h3 class="h5">1. Proponer</h3>
                    <p class="mb-0">La empresa describe su proyecto y la institución revisa sus objetivos, alcance y cupo antes de publicarlo.</p>
                </li>
                <li class="col-md-4">
                    <h3 class="h5">2. Participar</h3>
                    <p class="mb-0">Los alumnos presentan su candidatura y los profesores solicitan la dirección de los proyectos de su interés.</p>
                </li>
                <li class="col-md-4">
                    <h3 class="h5">3. Desarrollar</h3>
                    <p class="mb-0">La empresa evalúa a los candidatos. El administrador autoriza las asignaciones y confirma el inicio con alumnos y director.</p>
                </li>
            </ol>
        </div>
    </section>

    <section id="participantes" class="content-section participants-section" aria-labelledby="participantes-titulo">
        <div class="container">
            <h2 id="participantes-titulo">Un trabajo compartido</h2>
            <div class="row g-4 g-lg-5 mt-2">
                <div class="col-sm-6 col-lg-3">
                    <h3 class="h5">Empresas</h3>
                    <p class="mb-0">Plantean necesidades, proponen proyectos y evalúan a los alumnos interesados.</p>
                </div>
                <div class="col-sm-6 col-lg-3">
                    <h3 class="h5">Alumnos</h3>
                    <p class="mb-0">Comparten sus habilidades y se postulan a proyectos para ponerlas en práctica.</p>
                </div>
                <div class="col-sm-6 col-lg-3">
                    <h3 class="h5">Profesores</h3>
                    <p class="mb-0">Aportan su experiencia y acompañan el desarrollo de los proyectos como directores.</p>
                </div>
                <div class="col-sm-6 col-lg-3">
                    <h3 class="h5">Administración</h3>
                    <p class="mb-0">Revisa publicaciones, autoriza participantes y conserva el historial de las decisiones.</p>
                </div>
            </div>
        </div>
    </section>
@endsection
