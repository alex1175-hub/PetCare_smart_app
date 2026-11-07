# PetStation (app Flutter para Android)

Se conecta por Bluetooth LE al ESP32 (nombre `PetStation`) y muestra/envía los mismos datos que los topics MQTT.

## Preparar el proyecto
Requiere Flutter instalado (`flutter doctor`). Desde la raíz de este proyecto:

```
flutter pub get
flutter run          # con el celular conectado por USB y depuración USB activada
flutter build apk    # para generar el APK
```

## Uso
1. Enciende el ESP32 (con el firmware con Bluetooth, `USAR_BLE 1`).
2. Abre la app, acepta los permisos y toca **Conectar** en `PetStation`.
3. Verás sensores, programas y eventos en vivo; los botones envían ON/OFF y el programa de comida/agua.
4. En "Eventos y comandos" puedes escribir líneas como `puerta ON` o `petstation/config/agua {"cantidad":150,"intervalo_min":240}`.

## Configurar el WiFi de la estación
En la pantalla principal, tarjeta **WiFi de la estación** -> **Configurar WiFi** -> escribe red y contraseña. La estación prueba la red nueva 20 s; si no conecta, vuelve a la anterior. Se guarda en la memoria del ESP32 (sobrevive a reinicios).
Por seguridad se recomienda enviarla por Bluetooth (no por MQTT con un broker público).

## Protocolo
Servicio UART de Nordic (NUS): servicio `6E400001-...`, RX (app->ESP32) `6E400002-...`, TX (ESP32->app, notify) `6E400003-...`.
Una línea por mensaje: `<topic> <contenido>\n`.

No se puede probar en Wokwi (no simula Bluetooth): usa un ESP32 real.
