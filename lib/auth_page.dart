import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.child, this.authStateChanges});

  final Widget child;
  final Stream<User?>? authStateChanges;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authStateChanges ?? FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return snapshot.data == null ? const LoginPage() : child;
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = switch (e.code) {
          'invalid-email' => 'El correo electrónico no es válido.',
          'user-disabled' => 'Esta cuenta está deshabilitada.',
          'user-not-found' ||
          'invalid-credential' ||
          'wrong-password' =>
            'Correo o contraseña incorrectos.',
          'too-many-requests' => 'Demasiados intentos. Espera un momento.',
          _ => 'No fue posible iniciar sesión. (${e.code})',
        };
      });
    } catch (_) {
      setState(
          () => _error = 'No fue posible iniciar sesión. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(
          () => _error = 'Escribe tu correo para recuperar la contraseña.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Se envió un correo para restablecer la contraseña.')),
      );
      setState(() => _error = null);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = 'No fue posible enviar el correo. (${e.code})');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.pets,
                      size: 72, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'PetStation',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) {
                        return 'Escribe tu correo electrónico.';
                      }
                      if (!email.contains('@')) {
                        return 'Escribe un correo válido.';
                      }
                      return null;
                    },
                    enabled: !_loading,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                        icon: Icon(_obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off),
                      ),
                    ),
                    onFieldSubmitted: (_) => _loading ? null : _login(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Escribe tu contraseña.';
                      }
                      return null;
                    },
                    enabled: !_loading,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _loading ? null : _resetPassword,
                      child: const Text('¿Olvidaste tu contraseña?'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loading ? null : _login,
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                        _loading ? 'Iniciando sesión...' : 'Iniciar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
