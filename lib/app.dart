import 'package:flutter/material.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class ErpApp extends StatelessWidget {
  const ErpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ERP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}

/// Mostrado quando o app foi iniciado sem SUPABASE_URL / SUPABASE_ANON_KEY.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Supabase não configurado.\n\n'
              'Rode com: flutter run -d chrome --dart-define-from-file=env.json\n'
              'e na Vercel defina SUPABASE_URL e SUPABASE_ANON_KEY.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
