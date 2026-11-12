param(
    [ValidateSet('serve', 'artisan', 'composer', 'npm', 'php')]
    [string]$Task = 'serve'
)
$TaskArgs = $args
$ErrorActionPreference = 'Stop'
$portablePhp = Join-Path $PSScriptRoot '../.local/tools/php/php.exe'
$phpCommand = if (Test-Path -LiteralPath $portablePhp) { (Resolve-Path -LiteralPath $portablePhp).Path } else { (Get-Command php -ErrorAction Stop).Source }
$env:PATH = "$(Split-Path -Parent $phpCommand);$env:PATH"
Push-Location $PSScriptRoot
try {
    switch ($Task) {
        'serve' { & $phpCommand artisan serve --host=127.0.0.1 --port=8000 @TaskArgs }
        'artisan' { & $phpCommand artisan @TaskArgs }
        'php' { & $phpCommand @TaskArgs }
        'npm' { & npm.cmd @TaskArgs }
        'composer' {
            $portableComposer = Join-Path $PSScriptRoot '../.local/tools/composer.phar'
            if (Test-Path -LiteralPath $portableComposer) { & $phpCommand $portableComposer @TaskArgs }
            else { & composer @TaskArgs }
        }
    }
    $taskExitCode = $LASTEXITCODE
} finally { Pop-Location }
exit $taskExitCode
