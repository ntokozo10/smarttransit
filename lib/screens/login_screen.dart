import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/repository.dart';
import '../state/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _mfa = TextEditingController();
  bool _needMfa = false, _busy = false, _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    _mfa.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().login(_email.text, _pw.text, mfaCode: _mfa.text);
    } on MfaRequiredException {
      setState(() => _needMfa = true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fill(String e, String p) => setState(() {
        _email.text = e;
        _pw.text = p;
        _mfa.clear();
        _needMfa = false;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.directions_bus_filled_rounded, size: 64, color: cs.primary),
                  const SizedBox(height: 12),
                  Text('WSU SmartTransit',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                  Text('Route, residence & schedule management',
                      textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                        labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pw,
                    obscureText: _hide,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_needMfa) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _mfa,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                          labelText: 'Verification code (MFA)',
                          prefixIcon: Icon(Icons.shield_outlined)),
                      validator: (v) =>
                          (v == null || v.trim().length < 6) ? 'Enter the 6-digit code' : null,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: badColor)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_needMfa ? 'Verify & sign in' : 'Sign in'),
                  ),
                  if (AppConfig.useMock) ...[
                    const SizedBox(height: 28),
                    Text('Demo accounts (tap to fill)',
                        style: TextStyle(color: cs.outline, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final d in const [
                        ('Student', 'student1@wsu.ac.za', 'Student#123'),
                        ('Student (has pass)', 'student2@wsu.ac.za', 'Student#123'),
                        ('Driver', 'driver@wsu.ac.za', 'Driver#123'),
                        ('Officer', 'officer@wsu.ac.za', 'Officer#123'),
                        ('Manager', 'manager@wsu.ac.za', 'Manager#123'),
                        ('Super Admin', 'admin@wsu.ac.za', 'Admin#123'),
                      ])
                        ActionChip(label: Text(d.$1), onPressed: () => _fill(d.$2, d.$3)),
                    ]),
                    const SizedBox(height: 6),
                    Text('Privileged roles ask for MFA code 123456.',
                        style: TextStyle(color: cs.outline, fontSize: 12)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
