import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_service.dart';

final PetStationService servicio = PetStationService();

void main() => runApp(const PetStationApp());

class PetStationApp extends StatelessWidget {
  const PetStationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PetStation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true, brightness: Brightness.dark),
      home: ListenableBuilder(
        listenable: servicio,
        builder: (context, _) => servicio.estado == EstadoConexion.conectado
            ? const DashboardPage()
            : const ScanPage(),
      ),
    );
  }
}

// =====================================================================
// PANTALLA 1: buscar y conectar
// =====================================================================
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _todos = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _escanear());
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<bool> _permisos() async {
    final r = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final android12 = r[Permission.bluetoothScan]?.isGranted == true &&
        r[Permission.bluetoothConnect]?.isGranted == true;
    final android11 = r[Permission.locationWhenInUse]?.isGranted == true;
    return android12 || android11;
  }

  Future<void> _escanear() async {
    if (!await _permisos()) {
      _aviso('Se necesitan los permisos de Bluetooth para buscar la estación');
      return;
    }
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
    }
    try {
      await FlutterBluePlus.startScan(
        withServices: _todos ? <Guid>[] : [PetStationService.serviceUuid],
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      _aviso('No se pudo escanear: $e');
    }
  }

  String _nombre(ScanResult r) {
    final n = r.advertisementData.advName;
    if (n.isNotEmpty) return n;
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    return 'Sin nombre';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: servicio,
      builder: (context, _) {
        final conectando = servicio.estado == EstadoConexion.conectando;
        return Scaffold(
          appBar: AppBar(
            title: const Text('PetStation'),
            actions: [
              IconButton(
                tooltip: 'Buscar de nuevo',
                icon: const Icon(Icons.refresh),
                onPressed: conectando ? null : _escanear,
              ),
            ],
          ),
          body: Column(
            children: [
              StreamBuilder<bool>(
                stream: FlutterBluePlus.isScanning,
                initialData: false,
                builder: (context, snap) => (snap.data ?? false) || conectando
                    ? const LinearProgressIndicator()
                    : const SizedBox(height: 4),
              ),
              if (servicio.ultimoError != null)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.all(12),
                  child: Text(servicio.ultimoError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                ),
              SwitchListTile(
                title: const Text('Mostrar todos los dispositivos'),
                subtitle: const Text('Por defecto solo aparece "PetStation"'),
                value: _todos,
                onChanged: conectando
                    ? null
                    : (v) {
                        setState(() => _todos = v);
                        _escanear();
                      },
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<ScanResult>>(
                  stream: FlutterBluePlus.scanResults,
                  initialData: const [],
                  builder: (context, snap) {
                    final lista = [...(snap.data ?? <ScanResult>[])]
                      ..sort((a, b) => b.rssi.compareTo(a.rssi));
                    if (lista.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Buscando la estación PetStation...\n'
                            'Verifica que el ESP32 esté encendido y cerca.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = lista[i];
                        final esNuestra = _nombre(r) == 'PetStation';
                        return ListTile(
                          leading: Icon(esNuestra ? Icons.pets : Icons.bluetooth),
                          title: Text(_nombre(r)),
                          subtitle: Text('${r.device.remoteId.str}   ${r.rssi} dBm'),
                          trailing: FilledButton(
                            onPressed: conectando ? null : () => servicio.conectar(r.device),
                            child: const Text('Conectar'),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =====================================================================
// PANTALLA 2: monitoreo y control
// =====================================================================
double? _n(Map<String, dynamic>? m, String k) {
  final v = m?[k];
  return v is num ? v.toDouble() : null;
}

String _fmt(double? v, [int d = 1]) => v == null ? '--' : v.toStringAsFixed(d);

String _duracion(num? segundos) {
  if (segundos == null) return '--';
  final s = segundos.round();
  if (s >= 3600 && s % 3600 == 0) return '${s ~/ 3600} h';
  if (s >= 60 && s % 60 == 0) return '${s ~/ 60} min';
  if (s >= 60) return '${s ~/ 60} min ${s % 60} s';
  return '$s s';
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: servicio,
      builder: (context, _) {
        final s = servicio.sensores;
        final p = servicio.programacion;
        final nombre = servicio.dispositivo?.platformName ?? '';
        final tornilloOn = s?['puerta'] == 'ABIERTA';
        final bombaOn = s?['bomba'] == 'ON';
        final uhf = s?['uhf'] == true;

        return Scaffold(
          appBar: AppBar(
            title: Text(nombre.isEmpty ? 'PetStation' : nombre),
            actions: [
              IconButton(
                tooltip: 'Desconectar',
                icon: const Icon(Icons.bluetooth_disabled),
                onPressed: servicio.desconectar,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _Tarjeta(
                icono: Icons.bluetooth_connected,
                titulo: 'Estación',
                hijos: [
                  _Fila('Estado', servicio.estadoEstacion ?? 'conectado por Bluetooth'),
                  _Fila('Mascota (RFID UHF)', uhf ? 'Detectada' : 'No detectada'),
                  _Fila('Última lectura', s == null ? 'esperando datos...' : _hora(servicio.ultimaActualizacion)),
                ],
              ),
              _tarjetaWifi(context, servicio.wifi),
              _Tarjeta(
                icono: Icons.pets,
                titulo: 'Comida',
                hijos: [
                  _Nivel(
                    etiqueta: 'Contenedor',
                    pct: _n(s, 'contenedor_pct'),
                    alerta: s?['contenedor_vacio'] == true,
                    textoAlerta: s?['contenedor_ok'] == false ? 'Sin lectura del sensor' : 'Contenedor vacío',
                  ),
                  _Fila('Plato', '${_fmt(_n(s, 'plato_comida_g'))} g'),
                  _Fila('Tornillo sin fin', tornilloOn ? 'Girando' : 'Detenido'),
                  _Fila('Modo', '${s?['modo_puerta'] ?? '--'}'),
                  _Botones(
                    onEncender: () => servicio.setTornillo(true),
                    onApagar: () => servicio.setTornillo(false),
                  ),
                ],
              ),
              _Tarjeta(
                icono: Icons.water_drop,
                titulo: 'Agua',
                hijos: [
                  _Nivel(
                    etiqueta: 'Tanque',
                    pct: _n(s, 'tanque_pct'),
                    alerta: s?['tanque_vacio'] == true,
                    textoAlerta: s?['tanque_ok'] == false ? 'Sin lectura del sensor' : 'Tanque vacío',
                  ),
                  _Fila('Plato', '${_fmt(_n(s, 'plato_agua_g'))} g'),
                  _Fila('Bomba', bombaOn ? 'Encendida' : 'Apagada'),
                  _Fila('Modo', '${s?['modo_bomba'] ?? '--'}'),
                  _Botones(
                    onEncender: () => servicio.setBomba(true),
                    onApagar: () => servicio.setBomba(false),
                  ),
                ],
              ),
              _tarjetaPrograma(context, 'comida', 'Programa de comida', Icons.schedule, p),
              _tarjetaPrograma(context, 'agua', 'Programa de agua', Icons.schedule, p),
              const _ConsolaCard(),
            ],
          ),
        );
      },
    );
  }

  static String _hora(DateTime? h) {
    if (h == null) return '--';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(h.hour)}:${dos(h.minute)}:${dos(h.second)}';
  }

  Widget _tarjetaWifi(BuildContext context, Map<String, dynamic>? w) {
    final conectado = w?['conectado'] == true;
    final probando = w?['probando'] == true;
    final ssid = (w?['ssid'] ?? '').toString();
    return _Tarjeta(
      icono: conectado ? Icons.wifi : Icons.wifi_off,
      titulo: 'WiFi de la estación',
      hijos: [
        _Fila('Red', ssid.isEmpty ? '--' : ssid),
        _Fila('Estado', probando ? 'Probando red nueva...' : (w == null ? '--' : (conectado ? 'Conectado' : 'Sin conexión'))),
        _Fila('IP', conectado ? '${w?['ip']}' : '--'),
        _Fila('Señal', conectado ? '${w?['rssi']} dBm' : '--'),
        _Fila('Servidor MQTT', w == null ? '--' : (w['mqtt'] == true ? 'Conectado' : 'Sin conexión')),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Configurar WiFi'),
            onPressed: probando ? null : () => _configurarWifi(context),
          ),
        ),
      ],
    );
  }

  Future<void> _configurarWifi(BuildContext context) async {
    final ssid = TextEditingController();
    final clave = TextEditingController();
    var ver = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Configurar WiFi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ssid,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Nombre de la red (SSID)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: clave,
                obscureText: !ver,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  helperText: 'De 8 a 63 caracteres. Vacía si la red es abierta.',
                  suffixIcon: IconButton(
                    icon: Icon(ver ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => ver = !ver),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
          ],
        ),
      ),
    );
    final red = ssid.text.trim();
    final pass = clave.text;
    ssid.dispose();
    clave.dispose();
    if (ok != true || !context.mounted) return;

    String? error;
    if (red.isEmpty || red.length > 32) {
      error = 'Escribe el nombre de la red (máximo 32 caracteres)';
    } else if (pass.isNotEmpty && (pass.length < 8 || pass.length > 63)) {
      error = 'La contraseña debe tener de 8 a 63 caracteres';
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final enviado = await servicio.configurarWifi(red, pass);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(enviado
          ? 'Enviado. La estación probará la red durante unos 20 s; si no conecta, vuelve a la anterior.'
          : 'No se pudo enviar la configuración'),
    ));
  }

  Widget _tarjetaPrograma(BuildContext context, String clave, String titulo, IconData icono, Map<String, dynamic>? p) {
    final d = p?[clave] is Map<String, dynamic> ? p![clave] as Map<String, dynamic> : null;
    final unidad = d?['unidad'] ?? (clave == 'comida' ? 'g' : 'ml');
    final dispensando = d?['dispensando'] == true;
    return _Tarjeta(
      icono: icono,
      titulo: titulo,
      hijos: [
        _Fila('Cantidad', d == null ? '--' : '${_fmt(_n(d, 'cantidad'))} $unidad'),
        _Fila('Cada', _duracion(_n(d, 'intervalo_s'))),
        _Fila('Siguiente en', dispensando ? 'Dispensando ahora...' : _duracion(_n(d, 'proximo_s'))),
        _Fila('Último entregado', d == null ? '--' : '${_fmt(_n(d, 'ultimo_entregado'))} $unidad'),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text('Cambiar programa'),
            onPressed: () => _editarPrograma(context, clave, titulo, d),
          ),
        ),
      ],
    );
  }

  Future<void> _editarPrograma(BuildContext context, String clave, String titulo, Map<String, dynamic>? actual) async {
    final unidad = clave == 'comida' ? 'g' : 'ml';
    final cantidad = TextEditingController(text: _n(actual, 'cantidad')?.toStringAsFixed(0) ?? '');
    final intervaloS = _n(actual, 'intervalo_s');
    final intervalo = TextEditingController(
        text: intervaloS == null ? '' : (intervaloS / 60).toStringAsFixed(intervaloS % 60 == 0 ? 0 : 1));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cantidad,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cantidad por ración ($unidad)',
                helperText: clave == 'comida' ? 'De 5 a 200 g' : 'De 20 a 500 ml',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: intervalo,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Intervalo (minutos)',
                helperText: 'De 0.5 min a 1440 min (24 h)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final c = double.tryParse(cantidad.text.trim().replaceAll(',', '.'));
    final i = double.tryParse(intervalo.text.trim().replaceAll(',', '.'));
    if (c == null || i == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe números válidos')));
      return;
    }
    await servicio.configurar(clave, c, i);
  }
}

// ---------------------------------------------------------------- widgets
class _Tarjeta extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final List<Widget> hijos;
  const _Tarjeta({required this.icono, required this.titulo, required this.hijos});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icono),
              const SizedBox(width: 8),
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 12),
            for (final h in hijos) ...[h, const SizedBox(height: 8)],
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _Fila(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(etiqueta),
        Flexible(child: Text(valor, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }
}

class _Nivel extends StatelessWidget {
  final String etiqueta;
  final double? pct;
  final bool alerta;
  final String textoAlerta;
  const _Nivel({required this.etiqueta, required this.pct, required this.alerta, required this.textoAlerta});

  @override
  Widget build(BuildContext context) {
    final color = alerta ? Theme.of(context).colorScheme.error : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(etiqueta),
            Text('${_fmt(pct, 0)} %', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: ((pct ?? 0) / 100).clamp(0.0, 1.0),
          minHeight: 10,
          borderRadius: BorderRadius.circular(5),
          color: color,
        ),
        if (alerta)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(textoAlerta, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

class _Botones extends StatelessWidget {
  final VoidCallback onEncender;
  final VoidCallback onApagar;
  const _Botones({required this.onEncender, required this.onApagar});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onEncender,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Encender'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onApagar,
            icon: const Icon(Icons.stop),
            label: const Text('Apagar'),
          ),
        ),
      ],
    );
  }
}

class _ConsolaCard extends StatefulWidget {
  const _ConsolaCard();

  @override
  State<_ConsolaCard> createState() => _ConsolaCardState();
}

class _ConsolaCardState extends State<_ConsolaCard> {
  final _texto = TextEditingController();

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final linea = _texto.text;
    if (linea.trim().isEmpty) return;
    final ok = await servicio.enviarLinea(linea);
    if (ok) _texto.clear();
  }

  @override
  Widget build(BuildContext context) {
    final eventos = servicio.eventos.take(40).toList();
    return _Tarjeta(
      icono: Icons.terminal,
      titulo: 'Eventos y comandos',
      hijos: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _texto,
                decoration: const InputDecoration(
                  hintText: 'puerta ON  /  bomba OFF  /  comida {"cantidad":40}',
                  isDense: true,
                ),
                onSubmitted: (_) => _enviar(),
              ),
            ),
            IconButton(onPressed: _enviar, icon: const Icon(Icons.send)),
          ],
        ),
        if (eventos.isEmpty)
          const Text('Sin eventos todavía')
        else
          for (final e in eventos)
            Text(e, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ],
    );
  }
}
