param(
    [ValidateSet('Iniciar', 'Estado', 'Detener')]
    [string]$Accion = 'Iniciar'
)

$ErrorActionPreference = 'Stop'
$proyecto = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runtime = Join-Path $proyecto '.local/pruebas-publicas'
$estadoArchivo = Join-Path $runtime 'estado.json'
$puerto = 8088

function Proceso-Propio($datos, [string]$tipo) {
    $numero = $datos."${tipo}Pid"
    if (-not $numero) { return $null }
    $proceso = Get-Process -Id $numero -ErrorAction SilentlyContinue
    if ($proceso -and $proceso.Path -eq $datos."${tipo}Exe" -and
        $proceso.StartTime.ToUniversalTime().Ticks -eq $datos."${tipo}InicioTicks") {
        return $proceso
    }
    return $null
}

$estado = if (Test-Path -LiteralPath $estadoArchivo) { Get-Content -LiteralPath $estadoArchivo -Raw | ConvertFrom-Json }
if ($Accion -eq 'Estado') {
    if (-not $estado) { Write-Output 'No se ha iniciado la demostración pública.'; exit 0 }
    [pscustomobject]@{
        Enlace = $estado.url
        ServidorActivo = [bool](Proceso-Propio $estado 'web')
        TunelActivo = [bool](Proceso-Propio $estado 'tunel')
        Base = 'banco_pruebas_publicas'
    } | Format-List
    exit 0
}
if ($Accion -eq 'Detener') {
    if ($estado) {
        foreach ($tipo in @('tunel', 'web')) {
            $proceso = Proceso-Propio $estado $tipo
            if ($proceso) { Stop-Process -Id $proceso.Id }
        }
    }
    Write-Output 'Servicios públicos detenidos; los datos de prueba se conservan.'
    exit 0
}
if ($estado -and (Proceso-Propio $estado 'web') -and (Proceso-Propio $estado 'tunel')) {
    Write-Output $estado.url
    exit 0
}
if ($estado -and ((Proceso-Propio $estado 'web') -or (Proceso-Propio $estado 'tunel'))) {
    throw 'Hay un servicio público incompleto. Ejecutar primero: .\pruebas-publicas.ps1 Detener'
}
if (Get-NetTCPConnection -State Listen -LocalPort $puerto -ErrorAction SilentlyContinue) {
    throw "El puerto $puerto está ocupado; no se detiene ningún proceso ajeno."
}

$phpPortable = Join-Path $proyecto '.local/tools/php/php.exe'
$php = if (Test-Path -LiteralPath $phpPortable) { $phpPortable } else { (Get-Command php -ErrorAction Stop).Source }
$cloudflared = Join-Path $proyecto '.local/tools/cloudflared/cloudflared.exe'
if (-not (Test-Path -LiteralPath $cloudflared)) {
    throw "Falta cloudflared en $cloudflared. Consultar la guía web para instalarlo."
}
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'public/build/manifest.json'))) {
    throw 'Faltan los recursos compilados. Ejecutar .\dev.ps1 npm run build antes de iniciar.'
}
Push-Location $proyecto
try {
    & py -3.12 database/manage.py start
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar PostgreSQL.' }
    & py -3.12 database/preparar_demo_publica.py
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar la demostración pública.' }
} finally { Pop-Location }

$web = $null
$tunel = $null
try {
    $logTunel = Join-Path $runtime 'tunel-error.log'
    $tunel = Start-Process -FilePath $cloudflared -ArgumentList @('tunnel', '--no-autoupdate', '--protocol', 'http2', '--url', "http://127.0.0.1:$puerto") -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'tunel.log') -RedirectStandardError $logTunel
    $url = $null
    $limite = (Get-Date).AddSeconds(50)
    while ((Get-Date) -lt $limite -and -not $tunel.HasExited) {
        if (Test-Path -LiteralPath $logTunel) {
            $contenido = Get-Content -LiteralPath $logTunel -Raw
            if ($contenido -match 'https://[a-z0-9-]+\.trycloudflare\.com') { $url = $Matches[0]; break }
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $url) { throw "No se obtuvo el enlace de Cloudflare. Revisar $logTunel" }

    $privado = Get-Content -LiteralPath (Join-Path $runtime 'entorno.json') -Raw | ConvertFrom-Json
    $variables = @{
        APP_ENV = 'staging'
        APP_DEBUG = 'false'
        APP_KEY = $privado.APP_KEY
        APP_URL = $url
        BANCO_TUNEL_PUBLICO = 'true'
        DB_DATABASE = 'banco_pruebas_publicas'
        SESSION_COOKIE = 'banco_pruebas_publicas_session'
        SESSION_SECURE_COOKIE = 'true'
        LARAVEL_STORAGE_PATH = (Join-Path $runtime 'storage')
        APP_CONFIG_CACHE = (Join-Path $runtime 'config.php')
    }
    $anteriores = @{}
    foreach ($nombre in $variables.Keys) {
        $anteriores[$nombre] = [Environment]::GetEnvironmentVariable($nombre, 'Process')
        [Environment]::SetEnvironmentVariable($nombre, $variables[$nombre], 'Process')
    }
    try {
        # Misma resolución de PHP que dev.ps1; el directorio público es la única raíz HTTP.
        $router = Join-Path $PSScriptRoot 'vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php'
        $web = Start-Process -FilePath $php -ArgumentList @('-S', "127.0.0.1:$puerto", ('"' + $router + '"')) -WorkingDirectory (Join-Path $PSScriptRoot 'public') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'web.log') -RedirectStandardError (Join-Path $runtime 'web-error.log')
    } finally {
        foreach ($nombre in $variables.Keys) { [Environment]::SetEnvironmentVariable($nombre, $anteriores[$nombre], 'Process') }
    }
    Start-Sleep -Seconds 2
    if ($web.HasExited) { throw 'El servidor web no inició. Revisar .local/pruebas-publicas/web-error.log' }
    $estadoNuevo = @{
        url = $url
        webPid = $web.Id
        webExe = $web.Path
        webInicioTicks = $web.StartTime.ToUniversalTime().Ticks
        tunelPid = $tunel.Id
        tunelExe = $tunel.Path
        tunelInicioTicks = $tunel.StartTime.ToUniversalTime().Ticks
    }
    $estadoNuevo | ConvertTo-Json | Set-Content -LiteralPath $estadoArchivo -Encoding utf8
    Write-Output "Enlace público: $url/login"
    Write-Output 'Mantener este equipo encendido y conectado. Reiniciar el túnel genera otro enlace.'
} catch {
    if ($web -and -not $web.HasExited) { Stop-Process -Id $web.Id }
    if ($tunel -and -not $tunel.HasExited) { Stop-Process -Id $tunel.Id }
    throw
}
