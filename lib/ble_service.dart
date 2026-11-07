import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum EstadoConexion { desconectado, conectando, conectado }

/// Conexión Bluetooth LE con la estación (servicio UART de Nordic).
///
/// ESP32 -> app: líneas "<topic> <contenido>\n" por notificaciones (TX).
/// app -> ESP32: líneas "<topic> <contenido>\n" escritas en RX.
/// Son los mismos topics y contenidos que usa MQTT.
class PetStationService extends ChangeNotifier {
  static final Guid serviceUuid = Guid('6E400001-B5A3-F393-E0A9-F50E24DCCA9E');
  static final Guid rxUuid = Guid('6E400002-B5A3-F393-E0A9-F50E24DCCA9E'); // app -> ESP32
  static final Guid txUuid = Guid('6E400003-B5A3-F393-E0A9-F50E24DCCA9E'); // ESP32 -> app

  static const topicSensores = 'petstation/sensores';
  static const topicEventos = 'petstation/eventos';
  static const topicEstado = 'petstation/estado';
  static const topicProgramacion = 'petstation/programacion';
  static const topicPuerta = 'petstation/actuadores/puerta'; // motor del tornillo sin fin
  static const topicBomba = 'petstation/actuadores/bomba';
  static const topicCfgComida = 'petstation/config/comida';
  static const topicCfgAgua = 'petstation/config/agua';
  static const topicCfgWifi = 'petstation/config/wifi'; // {"ssid":..., "password":...}
  static const topicWifi = 'petstation/wifi'; // estado del WiFi de la estación

  EstadoConexion estado = EstadoConexion.desconectado;
  String? ultimoError;
  BluetoothDevice? dispositivo;

  Map<String, dynamic>? sensores;
  Map<String, dynamic>? programacion;
  Map<String, dynamic>? wifi;
  String? estadoEstacion;
  DateTime? ultimaActualizacion;
  final List<String> eventos = []; // el más reciente primero

  BluetoothCharacteristic? _rx;
  StreamSubscription<List<int>>? _txSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final List<int> _bytes = [];

  // ---------------------------------------------------------------- conexión
  Future<void> conectar(BluetoothDevice d) async {
    if (estado == EstadoConexion.conectando) return;
    ultimoError = null;
    estado = EstadoConexion.conectando;
    notifyListeners();

    try {
      await FlutterBluePlus.stopScan();
      await d.connect(timeout: const Duration(seconds: 15));
      dispositivo = d;

      final servicios = await d.discoverServices();
      final nus = servicios.firstWhere(
        (s) => s.uuid == serviceUuid,
        orElse: () => throw Exception('Este dispositivo no es una estación PetStation'),
      );
      final rx = nus.characteristics.firstWhere(
        (c) => c.uuid == rxUuid,
        orElse: () => throw Exception('Falta la característica RX'),
      );
      final tx = nus.characteristics.firstWhere(
        (c) => c.uuid == txUuid,
        orElse: () => throw Exception('Falta la característica TX'),
      );

      _bytes.clear();
      _txSub = tx.onValueReceived.listen(_alRecibir);
      await tx.setNotifyValue(true);
      _rx = rx;

      _connSub = d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _alDesconectar();
      });

      estado = EstadoConexion.conectado;
      _log('Conectado a ${_nombreDe(d)}');
      notifyListeners();
    } catch (e) {
      ultimoError = e.toString().replaceFirst('Exception: ', '');
      await _limpiar(desconectar: true);
      estado = EstadoConexion.desconectado;
      notifyListeners();
    }
  }

  Future<void> desconectar() async {
    await _limpiar(desconectar: true);
    estado = EstadoConexion.desconectado;
    ultimoError = null;
    _reiniciarDatos();
    notifyListeners();
  }

  Future<void> _alDesconectar() async {
    if (estado == EstadoConexion.desconectado) return;
    await _limpiar(desconectar: false);
    estado = EstadoConexion.desconectado;
    ultimoError = 'Se perdió la conexión con la estación';
    _reiniciarDatos();
    notifyListeners();
  }

  Future<void> _limpiar({required bool desconectar}) async {
    await _txSub?.cancel();
    _txSub = null;
    await _connSub?.cancel();
    _connSub = null;
    _rx = null;
    if (desconectar) {
      try {
        await dispositivo?.disconnect();
      } catch (_) {}
    }
    dispositivo = null;
  }

  void _reiniciarDatos() {
    sensores = null;
    programacion = null;
    wifi = null;
    estadoEstacion = null;
    ultimaActualizacion = null;
  }

  // ---------------------------------------------------------------- recepción
  void _alRecibir(List<int> datos) {
    if (datos.isEmpty) return;
    _bytes.addAll(datos);
    int i;
    while ((i = _bytes.indexOf(10)) >= 0) {
      final linea = utf8.decode(_bytes.sublist(0, i), allowMalformed: true).trim();
      _bytes.removeRange(0, i + 1);
      if (linea.isNotEmpty) _procesarLinea(linea);
    }
    if (_bytes.length > 4000) _bytes.clear();
  }

  void _procesarLinea(String linea) {
    final sp = linea.indexOf(' ');
    final topic = sp < 0 ? linea : linea.substring(0, sp);
    final payload = sp < 0 ? '' : linea.substring(sp + 1).trim();

    switch (topic) {
      case topicSensores:
        final d = _json(payload);
        if (d != null) {
          sensores = d;
          ultimaActualizacion = DateTime.now();
        }
        break;
      case topicProgramacion:
        final d = _json(payload);
        if (d != null) programacion = d;
        break;
      case topicWifi:
        final d = _json(payload);
        if (d != null) wifi = d;
        break;
      case topicEstado:
        estadoEstacion = payload;
        break;
      case topicEventos:
        _log(payload);
        break;
      default:
        _log(linea);
    }
    notifyListeners();
  }

  Map<String, dynamic>? _json(String texto) {
    try {
      final d = jsonDecode(texto);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- envío
  Future<bool> enviar(String topic, String contenido) async {
    final rx = _rx;
    if (rx == null || estado != EstadoConexion.conectado) return false;
    try {
      await rx.write(utf8.encode('$topic $contenido\n'), allowLongWrite: true);
      // la contraseña de WiFi nunca se guarda en el registro
      _log(topic == topicCfgWifi ? '→ $topic (contenido oculto)' : '→ $topic $contenido');
      notifyListeners();
      return true;
    } catch (e) {
      _log('Error al enviar: $e');
      notifyListeners();
      return false;
    }
  }

  /// Envía una línea escrita a mano: "topic contenido" (o nombre corto: "puerta ON").
  Future<bool> enviarLinea(String linea) {
    linea = linea.trim();
    final sp = linea.indexOf(' ');
    if (linea.isEmpty) return Future.value(false);
    if (sp < 0) return enviar(linea, '');
    return enviar(linea.substring(0, sp), linea.substring(sp + 1).trim());
  }

  Future<bool> setTornillo(bool encendido) => enviar(topicPuerta, encendido ? 'ON' : 'OFF');
  Future<bool> setBomba(bool encendida) => enviar(topicBomba, encendida ? 'ON' : 'OFF');

  /// clave: "comida" o "agua". intervalo en minutos (admite decimales).
  Future<bool> configurar(String clave, double cantidad, double intervaloMin) {
    final topic = clave == 'comida' ? topicCfgComida : topicCfgAgua;
    return enviar(topic, jsonEncode({'cantidad': cantidad, 'intervalo_min': intervaloMin}));
  }

  /// Envía la red y la contraseña a la estación. Si la red nueva no conecta en 20 s,
  /// la estación vuelve a la anterior. Contraseña vacía = red abierta.
  Future<bool> configurarWifi(String ssid, String password) =>
      enviar(topicCfgWifi, jsonEncode({'ssid': ssid, 'password': password}));

  // ---------------------------------------------------------------- utilidades
  String _nombreDe(BluetoothDevice d) => d.platformName.isNotEmpty ? d.platformName : d.remoteId.str;

  void _log(String texto) {
    final h = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    eventos.insert(0, '${dos(h.hour)}:${dos(h.minute)}:${dos(h.second)}  $texto');
    if (eventos.length > 100) eventos.removeLast();
  }
}
