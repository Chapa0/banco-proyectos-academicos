<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>@yield('title') · Banco de proyectos</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="workspace-page">
    <main class="container auth-section" id="contenido">
        <section class="surface auth-surface">
            <h1 class="page-title">@yield('heading')</h1>
            <p class="page-description mb-4">@yield('message')</p>
            @yield('action')
        </section>
    </main>
</body>
</html>
