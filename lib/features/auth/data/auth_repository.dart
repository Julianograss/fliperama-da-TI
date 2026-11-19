import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository._();
  static final instance = AuthRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Retorna true se já abriu sessão; false se for preciso confirmar o e-mail.
  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name},
    );
    return res.session != null;
  }

  Future<void> signOut() => _client.auth.signOut();
}
