<?php

use App\Http\Controllers\Admin\CuentaController;
use App\Http\Controllers\Admin\RevisionProyectoController;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\AvisoController;
use App\Http\Controllers\CatalogoController;
use App\Http\Controllers\ClaveController;
use App\Http\Controllers\DocumentoController;
use App\Http\Controllers\EmpresaController;
use App\Http\Controllers\InicioController;
use App\Http\Controllers\PanelController;
use App\Http\Controllers\ParticipacionController;
use App\Http\Controllers\PerfilController;
use App\Http\Controllers\ProyectoController;
use App\Http\Controllers\ReporteController;
use App\Http\Controllers\SeguimientoController;
use Illuminate\Support\Facades\Route;

Route::get('/', InicioController::class)->name('inicio');

Route::middleware('guest')->group(function () {
    Route::get('/login', [AuthController::class, 'create'])->name('login');
    Route::post('/login', [AuthController::class, 'store'])->name('login.store');
});

Route::middleware(['auth', 'cuenta.activa'])->group(function () {
    Route::post('/logout', [AuthController::class, 'destroy'])->name('logout');
    Route::get('/clave', [ClaveController::class, 'edit'])->name('clave.edit');
    Route::put('/clave', [ClaveController::class, 'update'])->middleware('throttle:6,1')->name('clave.update');

    Route::middleware('clave.actualizada')->group(function () {
        Route::get('/panel', PanelController::class)->name('panel');
        Route::get('/documentos/{documento}', [DocumentoController::class, 'show'])->where('documento', '-?[0-9]+')->middleware('throttle:60,1')->name('documentos.show');
        Route::prefix('avisos')->name('avisos.')->middleware('can:consultar-avisos')->group(function () {
            Route::get('/', [AvisoController::class, 'index'])->name('index');
            Route::get('/{aviso}', [AvisoController::class, 'show'])->where('aviso', '-?[0-9]+')->name('show');
            Route::post('/{aviso}/leer', [AvisoController::class, 'leer'])->where('aviso', '-?[0-9]+')->name('leer');
        });
        Route::get('/reportes/{tipo}/exportar', [ReporteController::class, 'exportar'])->middleware(['can:consultar-reportes', 'throttle:10,1'])
            ->where('tipo', 'proyectos|candidaturas|direcciones|carga_profesores|asignaciones')->name('reportes.exportar');
        Route::get('/reportes/{tipo?}', [ReporteController::class, 'index'])->middleware('can:consultar-reportes')
            ->where('tipo', 'proyectos|candidaturas|direcciones|carga_profesores|asignaciones')->name('reportes.index');
        Route::middleware('can:participar')->group(function () {
            Route::get('/catalogo/{proyecto}/participar', [ParticipacionController::class, 'create'])->where('proyecto', '-?[0-9]+')->name('participacion.create');
            Route::post('/catalogo/{proyecto}/participar', [ParticipacionController::class, 'store'])->where('proyecto', '-?[0-9]+')->name('participacion.store');
        });
        Route::prefix('participacion')->name('participacion.')->middleware('can:consultar-participacion')->group(function () {
            Route::get('/{tipo}', [ParticipacionController::class, 'index'])->where('tipo', 'candidatura|direccion')->name('index');
            Route::get('/{tipo}/{solicitud}', [ParticipacionController::class, 'show'])->where(['tipo' => 'candidatura|direccion', 'solicitud' => '-?[0-9]+'])->name('show');
            Route::post('/{tipo}/{solicitud}/{accion}', [ParticipacionController::class, 'operar'])
                ->where(['tipo' => 'candidatura|direccion', 'solicitud' => '-?[0-9]+', 'accion' => 'cancelar|evaluar|preseleccionar|aprobar|rechazar'])->name('operar');
        });
        Route::prefix('seguimiento/proyectos')->name('seguimiento.')->middleware('can:consultar-participacion')->group(function () {
            Route::get('/', [SeguimientoController::class, 'index'])->name('index');
            Route::get('/{proyecto}', [SeguimientoController::class, 'show'])->where('proyecto', '-?[0-9]+')->name('show');
            Route::post('/{proyecto}/{accion}', [SeguimientoController::class, 'operar'])->middleware('can:gestionar-ciclo')
                ->where(['proyecto' => '-?[0-9]+', 'accion' => 'iniciar|reanudar|finalizar|cancelar|retirar_alumno|retirar_director'])->name('operar');
        });
        Route::middleware('can:gestionar-perfil')->group(function () {
            Route::get('/perfil', [PerfilController::class, 'edit'])->name('perfil.edit');
            Route::put('/perfil', [PerfilController::class, 'update'])->name('perfil.update');
            Route::post('/perfil/documentos', [DocumentoController::class, 'store'])->middleware('throttle:20,1')->name('documentos.store');
            Route::delete('/perfil/documentos/{documento}', [DocumentoController::class, 'destroy'])->where('documento', '-?[0-9]+')->name('documentos.destroy');
        });
        Route::middleware('can:consultar-catalogo')->group(function () {
            Route::get('/catalogo', [CatalogoController::class, 'index'])->name('catalogo.index');
            Route::get('/catalogo/{proyecto}', [CatalogoController::class, 'show'])->where('proyecto', '-?[0-9]+')->name('catalogo.show');
        });
        Route::middleware('can:gestionar-proyectos')->group(function () {
            Route::get('/empresa', [EmpresaController::class, 'edit'])->name('empresa.edit');
            Route::put('/empresa', [EmpresaController::class, 'update'])->name('empresa.update');
            Route::prefix('empresa/proyectos')->name('proyectos.')->group(function () {
                Route::get('/', [ProyectoController::class, 'index'])->name('index');
                Route::get('/crear', [ProyectoController::class, 'create'])->name('create');
                Route::post('/', [ProyectoController::class, 'store'])->name('store');
                Route::get('/{proyecto}', [ProyectoController::class, 'show'])->where('proyecto', '-?[0-9]+')->name('show');
                Route::get('/{proyecto}/editar', [ProyectoController::class, 'edit'])->where('proyecto', '-?[0-9]+')->name('edit');
                Route::put('/{proyecto}', [ProyectoController::class, 'update'])->where('proyecto', '-?[0-9]+')->name('update');
                Route::post('/{proyecto}/enviar', [ProyectoController::class, 'enviar'])->where('proyecto', '-?[0-9]+')->name('enviar');
            });
        });
        Route::prefix('admin/proyectos')->name('revision.')->middleware('can:revisar-proyectos')->group(function () {
            Route::get('/', [RevisionProyectoController::class, 'index'])->name('index');
            Route::get('/{proyecto}', [RevisionProyectoController::class, 'show'])->where('proyecto', '-?[0-9]+')->name('show');
            Route::post('/{proyecto}/resolver', [RevisionProyectoController::class, 'resolver'])->where('proyecto', '-?[0-9]+')->name('resolver');
        });
        Route::prefix('admin/cuentas')->name('cuentas.')->middleware('can:administrar-cuentas')->group(function () {
            Route::get('/', [CuentaController::class, 'index'])->name('index');
            Route::get('/crear', [CuentaController::class, 'create'])->name('create');
            Route::post('/', [CuentaController::class, 'store'])->name('store');
            Route::get('/{cuenta}/editar', [CuentaController::class, 'edit'])->where('cuenta', '-?[0-9]+')->name('edit');
            Route::put('/{cuenta}', [CuentaController::class, 'update'])->where('cuenta', '-?[0-9]+')->name('update');
            Route::post('/{cuenta}/estado', [CuentaController::class, 'estado'])->where('cuenta', '-?[0-9]+')->name('estado');
            Route::post('/{cuenta}/clave', [CuentaController::class, 'clave'])->where('cuenta', '-?[0-9]+')->name('clave');
            Route::post('/{cuenta}/relevo', [CuentaController::class, 'relevo'])->where('cuenta', '-?[0-9]+')->name('relevo');
        });
    });
});
