import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/home/presentation/app_shell.dart';
import '../../features/home/presentation/dashboard_page.dart';
import '../../features/inventory/presentation/products_page.dart';
import '../../features/sectors/presentation/sectors_page.dart';
import '../../shared/module_placeholder_page.dart';
import 'package:flutter/material.dart';

/// Faz o GoRouter reavaliar o redirect quando o login/logout acontece.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

const _publicPaths = {'/login', '/register'};

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: _AuthRefresh(AuthRepository.instance.authChanges),
  redirect: (context, state) {
    final loggedIn = AuthRepository.instance.currentSession != null;
    final isPublic = _publicPaths.contains(state.uri.path);

    if (!loggedIn && !isPublic) return '/login';
    if (loggedIn && isPublic) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
        GoRoute(path: '/estoque', builder: (_, __) => const ProductsPage()),
        GoRoute(path: '/setores', builder: (_, __) => const SectorsPage()),
        GoRoute(
          path: '/compras',
          builder: (_, __) => const ModulePlaceholderPage(
            title: 'Compras',
            icon: Icons.shopping_cart_outlined,
          ),
        ),
        GoRoute(
          path: '/vendas',
          builder: (_, __) => const ModulePlaceholderPage(
            title: 'Vendas',
            icon: Icons.point_of_sale_outlined,
          ),
        ),
        GoRoute(
          path: '/financeiro',
          builder: (_, __) => const ModulePlaceholderPage(
            title: 'Financeiro',
            icon: Icons.account_balance_outlined,
          ),
        ),
        GoRoute(
          path: '/rh',
          builder: (_, __) => const ModulePlaceholderPage(
            title: 'Recursos Humanos',
            icon: Icons.groups_outlined,
          ),
        ),
      ],
    ),
  ],
);
