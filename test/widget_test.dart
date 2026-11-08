import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:petcare_smart_app_mk2/auth_page.dart';
import 'package:petcare_smart_app_mk2/ble_service.dart';
import 'package:petcare_smart_app_mk2/main.dart';

void main() {
  testWidgets('PetStation dashboard renders when connected', (tester) async {
    servicio.estado = EstadoConexion.conectado;
    addTearDown(() => servicio.estado = EstadoConexion.desconectado);

    final user = MockUser(uid: 'test-user', email: 'admin@petcare.com');
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          authStateChanges: Stream.value(user),
          child: const DashboardPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('PetStation'), findsOneWidget);
    expect(find.text('WiFi de la estación'), findsOneWidget);
  });
}
