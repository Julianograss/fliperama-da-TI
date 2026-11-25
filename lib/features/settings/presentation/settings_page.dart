import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/user_session.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/data/auth_repository.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = UserSession.instance.user;
    if (user == null) return const AccessDenied();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle('Configurações'),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Minha conta',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _line('Nome', user.nome),
                _line('E-mail', user.email ?? '-'),
                _line('Nível de acesso', user.perfilNome),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    UserSession.instance.reset();
                    AuthRepository.instance.signOut();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sair do sistema'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Panel(
            child: FutureBuilder(
              future: Supabase.instance.client
                  .from('perfis_acesso')
                  .select()
                  .order('nome'),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Text(errorMessage(snap.error!));
                }
                final rows = List<Map<String, dynamic>>.from(snap.data as List);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Níveis de acesso',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final r in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.shield_outlined),
                        title: Text('${r['nome']}'),
                        subtitle: Text('${r['descricao']}'),
                      ),
                    const Text(
                      'As permissões são validadas no banco de dados (RLS e funções), '
                      'não apenas nas telas.',
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 130, child: Text(label)),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
