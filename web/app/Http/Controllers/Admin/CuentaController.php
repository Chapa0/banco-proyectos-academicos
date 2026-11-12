<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Cuentas\CrearCuentaRequest;
use App\Http\Requests\Cuentas\EditarCuentaRequest;
use App\Http\Requests\Cuentas\EstadoCuentaRequest;
use App\Http\Requests\Cuentas\RelevarRepresentanteRequest;
use App\Http\Requests\Cuentas\RestablecerClaveRequest;
use App\Services\CuentaService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;
use Illuminate\View\View;

class CuentaController extends Controller
{
    public function __construct(private readonly CuentaService $cuentas) {}

    public function index(Request $request): View
    {
        Gate::authorize('administrar-cuentas');
        $filtros = $request->validate([
            'buscar' => ['nullable', 'string', 'max:100'],
            'rol' => ['nullable', Rule::in(['administrador', 'empresa', 'alumno', 'profesor'])],
            'estado' => ['nullable', Rule::in(['activa', 'inactiva'])],
            'page' => ['nullable', 'integer', 'min:1', 'max:10000'],
        ]);

        return view('cuentas.index', [
            'cuentas' => $this->cuentas->listar((int) $request->user()->getAuthIdentifier(), $filtros, (int) ($filtros['page'] ?? 1)),
            'filtros' => $filtros,
        ]);
    }

    public function create(): View
    {
        Gate::authorize('administrar-cuentas');

        return view('cuentas.create');
    }

    public function store(CrearCuentaRequest $request): RedirectResponse
    {
        Gate::authorize('administrar-cuentas');
        $cuenta = $this->cuentas->crear((int) $request->user()->getAuthIdentifier(), $request->validated());

        return redirect()->route('cuentas.edit', $cuenta)
            ->with('status', 'Cuenta creada. Entrega la contraseña temporal por el canal acordado; la persona deberá cambiarla al entrar.');
    }

    public function edit(Request $request, int $cuenta): View
    {
        Gate::authorize('administrar-cuentas');

        return view('cuentas.edit', ['cuenta' => $this->cuentas->obtener((int) $request->user()->getAuthIdentifier(), $cuenta)]);
    }

    public function update(EditarCuentaRequest $request, int $cuenta): RedirectResponse
    {
        Gate::authorize('administrar-cuentas');
        $this->cuentas->editar((int) $request->user()->getAuthIdentifier(), $cuenta, $request->validated());

        return redirect()->route('cuentas.edit', $cuenta)->with('status', 'Datos de la cuenta actualizados.');
    }

    public function estado(EstadoCuentaRequest $request, int $cuenta): RedirectResponse
    {
        Gate::authorize('administrar-cuentas');
        $this->cuentas->cambiarEstado((int) $request->user()->getAuthIdentifier(), $cuenta, $request->validated());

        return redirect()->route('cuentas.edit', $cuenta)->with('status', 'Estado actualizado. Las participaciones y su historial se conservaron.');
    }

    public function clave(RestablecerClaveRequest $request, int $cuenta): RedirectResponse
    {
        Gate::authorize('administrar-cuentas');
        $this->cuentas->restablecerClave((int) $request->user()->getAuthIdentifier(), $cuenta, $request->validated());

        return redirect()->route('cuentas.edit', $cuenta)
            ->with('status', 'Contraseña temporal restablecida. Entrega la nueva contraseña por el canal acordado; el cambio será obligatorio al entrar.');
    }

    public function relevo(RelevarRepresentanteRequest $request, int $cuenta): RedirectResponse
    {
        Gate::authorize('administrar-cuentas');
        $admin = (int) $request->user()->getAuthIdentifier();
        $anterior = $this->cuentas->obtener($admin, $cuenta);
        abort_unless($anterior->rol_principal === 'empresa' && $anterior->representante_vigente && $anterior->empresa_id !== null, 403);
        $nueva = $this->cuentas->relevar($admin, $anterior, $request->validated());

        return redirect()->route('cuentas.edit', $nueva)
            ->with('status', 'Representante sustituido. La cuenta anterior quedó inactiva y conservó su vínculo e historial. Entrega la contraseña temporal al nuevo representante.');
    }
}
