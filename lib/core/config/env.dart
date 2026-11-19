/// Valores injetados no build com --dart-define / --dart-define-from-file.
class Env {
  static const supabaseUrl = String.fromEnvironment('https://xntabivlehiepwgmmosk.supabase.co');
  static const supabaseAnonKey = String.fromEnvironment('sb_publishable_qK6Tmwybm2-upbYnaN5M7w_L0dpT3y6');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
