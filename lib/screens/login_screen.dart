import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../state/auth.dart';

/// Sign in with CAAS credentials. Mirrors the web LoginPage: username,
/// password (show/hide), "keep me signed in", and a disabled organisation-SSO
/// button (SSO isn't available yet).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _keepSignedIn = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return;
    FocusScope.of(context).unfocus();
    ref.read(authProvider.notifier).login(_username.text.trim(), _password.text, keepSignedIn: _keepSignedIn);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/blue_fill_logo.png', height: 120),
                  const SizedBox(height: 16),
                  Text('Sign in', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Use the credentials issued by your organisation administrator.',
                      style: TextStyle(color: AppColors.grey600)),
                  const SizedBox(height: 24),
                  if (auth.error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.red100, borderRadius: BorderRadius.circular(6)),
                      child: Text(auth.error!, style: const TextStyle(color: AppColors.red600, fontSize: 13)),
                    ),
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(labelText: 'Username'),
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? 'Hide password' : 'Show password',
                        icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _keepSignedIn,
                    onChanged: (v) => setState(() => _keepSignedIn = v ?? false),
                    title: const Text('Keep me signed in on this device'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: auth.loading ? null : _submit,
                    child: Text(auth.loading ? 'Signing in…' : 'Sign in'),
                  ),
                  const SizedBox(height: 16),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or', style: TextStyle(color: AppColors.grey500))),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 16),
                  // Shown but disabled — organisation SSO isn't available yet.
                  const Tooltip(
                    message: "Organisation SSO isn't available yet",
                    child: OutlinedButton(onPressed: null, child: Text('Continue with organisation SSO')),
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
