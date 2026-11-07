import 'package:flutter_test/flutter_test.dart';

import 'package:petcare_smart_app_mk2/ble_service.dart';
import 'package:petcare_smart_app_mk2/main.dart';

void main() {
  testWidgets('PetStation dashboard renders when connected', (tester) async {
    servicio.estado = EstadoConexion.conectado;
    addTearDown(() => servicio.estado = EstadoConexion.desconectado);

    await tester.pumpWidget(const PetStationApp());

    expect(find.text('PetStation'), findsOneWidget);
    expect(find.text('WiFi de la estación'), findsOneWidget);
  });
}
