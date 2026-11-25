import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/format.dart';

class CurrentUser {
  CurrentUser({
    required this.id,
    required this.nome,
    required this.perfil,
    required this.ativo,
    this.email,
  });

  final String id;
  final String nome;
  final String perfil;
  final bool ativo;
  final String? email;

  bool get isAdmin => perfil == 'administrador';
  bool get isGestor => perfil == 'administrador' || perfil == 'gerente';

  String get perfilNome {
    switch (perfil) {
      case 'administrador':
        return 'Administrador';
      case 'gerente':
        return 'Gerente';
      case 'operador_caixa':
        return 'Operador de Caixa';
      case 'tecnico':
        return 'Técnico';
      default:
        return perfil;
    }
  }
}

const _todos = {'administrador', 'gerente', 'operador_caixa', 'tecnico'};
const _gestores = {'administrador', 'gerente'};

/// Quem pode abrir cada tela (o banco valida de novo via RLS/RPC).
const Map<String, Set<String>> routeAccess = {
  '/': _todos,
  '/pdv': {'administrador', 'gerente', 'operador_caixa'},
  '/estoque': _gestores,
  '/entradas': _gestores,
  '/saidas': {'administrador', 'gerente', 'tecnico'},
  '/maquinas': {'administrador', 'gerente', 'tecnico'},
  '/fornecedores': _gestores,
  '/funcionarios': _gestores,
  '/escalas': _todos,
  '/caixa': {'administrador', 'gerente', 'operador_caixa'},
  '/contas': _gestores,
  '/relatorios': {'administrador', 'gerente', 'tecnico'},
  '/configuracoes': _todos,
};

bool canAccess(String perfil, String path) =>
    routeAccess[path]?.contains(perfil) ?? false;

class UserSession extends ChangeNotifier {
  UserSession._();
  static final instance = UserSession._();

  CurrentUser? user;
  bool loaded = false;
  String? error;

  /// Limpa o estado sem notificar (usado ao entrar/sair).
  void reset() {
    user = null;
    loaded = false;
    error = null;
  }

  Future<void> load() async {
    final auth = Supabase.instance.client.auth.currentUser;
    if (auth == null) {
      reset();
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('colaboradores')
          .select()
          .eq('user_id', auth.id)
          .maybeSingle();
      user = row == null
          ? null
          : CurrentUser(
              id: row['id'] as String,
              nome: (row['nome_completo'] ?? '') as String,
              perfil: row['perfil_id'] as String,
              ativo: row['ativo'] == true,
              email: row['email'] as String?,
            );
      error = null;
    } catch (e) {
      error = errorMessage(e);
    }
    loaded = true;
    notifyListeners();
  }
}
