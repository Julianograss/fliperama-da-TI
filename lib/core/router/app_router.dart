import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/cash/presentation/cash_page.dart';
import '../../features/employees/presentation/employees_page.dart';
import '../../features/finance/presentation/accounts_page.dart';
import '../../features/home/presentation/app_shell.dart';
import '../../features/home/presentation/dashboard_page.dart';
import '../../features/inventory/presentation/entries_page.dart';
import '../../features/inventory/presentation/exits_page.dart';
import '../../features/inventory/presentation/products_page.dart';
import '../../features/machines/presentation/machines_page.dart';
import '../../features/reports/presentation/reports_page.dart';
import '../../features/sales/presentation/pdv_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shifts/presentation/shifts_page.dart';
import '../../features/suppliers/presentation/suppliers_page.dart';

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
        GoRoute(path: '/pdv', builder: (_, __) => const PdvPage()),
        GoRoute(path: '/estoque', builder: (_, __) => const ProductsPage()),
        GoRoute(path: '/entradas', builder: (_, __) => const EntriesPage()),
        GoRoute(path: '/saidas', builder: (_, __) => const ExitsPage()),
        GoRoute(path: '/maquinas', builder: (_, __) => const MachinesPage()),
        GoRoute(
            path: '/fornecedores', builder: (_, __) => const SuppliersPage()),
        GoRoute(
            path: '/funcionarios', builder: (_, __) => const EmployeesPage()),
        GoRoute(path: '/escalas', builder: (_, __) => const ShiftsPage()),
        GoRoute(path: '/caixa', builder: (_, __) => const CashPage()),
        GoRoute(path: '/contas', builder: (_, __) => const AccountsPage()),
        GoRoute(path: '/relatorios', builder: (_, __) => const ReportsPage()),
        GoRoute(
            path: '/configuracoes', builder: (_, __) => const SettingsPage()),
      ],
    ),
  ],
);
