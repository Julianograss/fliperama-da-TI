import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import 'auth_scaffold.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final signedIn = await AuthRepository.instance.signUp(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!signedIn && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Conta criada! Confirme seu e-mail para poder entrar.'),
          ),
        );
        context.go('/login');
      }
      // Se já abriu sessão, o redirect do router leva para o dashboard.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Criar conta',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome completo'),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Informe seu nome'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Informe o e-mail';
                if (!value.contains('@')) return 'E-mail inválido';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Senha',
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.length < 6)
                  ? 'Mínimo de 6 caracteres'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              onFieldSubmitted: (_) => _submit(),
              decoration:
                  const InputDecoration(labelText: 'Confirmar senha'),
              validator: (v) =>
                  v != _password.text ? 'As senhas não conferem' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Cadastrar'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Já tem conta? Entrar'),
            ),
          ],
        ),
      ),
    );
  }
}
