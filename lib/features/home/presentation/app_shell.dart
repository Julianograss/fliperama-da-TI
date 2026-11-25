import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/user_session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/data/auth_repository.dart';

class _NavItem {
  const _NavItem(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

const _items = [
  _NavItem('/', 'Dashboard', Icons.dashboard_outlined),
  _NavItem('/pdv', 'PDV / Vendas', Icons.point_of_sale),
  _NavItem('/estoque', 'Produtos e Estoque', Icons.inventory_2_outlined),
  _NavItem('/entradas', 'Entradas de Mercadorias', Icons.move_to_inbox_outlined),
  _NavItem('/saidas', 'Saídas de Estoque', Icons.outbox_outlined),
  _NavItem('/maquinas', 'Máquinas Arcade', Icons.sports_esports_outlined),
  _NavItem('/fornecedores', 'Fornecedores', Icons.local_shipping_outlined),
  _NavItem('/funcionarios', 'Funcionários', Icons.badge_outlined),
  _NavItem('/escalas', 'Escalas e Turnos', Icons.schedule_outlined),
  _NavItem('/caixa', 'Controle de Caixa', Icons.account_balance_wallet_outlined),
  _NavItem('/contas', 'Contas a Pagar e Receber', Icons.receipt_long_outlined),
  _NavItem('/relatorios', 'Relatórios', Icons.bar_chart_outlined),
  _NavItem('/configuracoes', 'Configurações', Icons.settings_outlined),
];

/// Estrutura das telas logadas: menu lateral (desktop) ou gaveta (celular/tablet).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _session = UserSession.instance;

  @override
  void initState() {
    super.initState();
    _session.reset();
    _session.addListener(_onSession);
    _session.load();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    _session.reset();
    await AuthRepository.instance.signOut();
  }

  String get _currentPath {
    final loc = widget.location;
    for (final i in _items) {
      if (i.path != '/' && loc.startsWith(i.path)) return i.path;
    }
    return '/';
  }

  @override
  Widget build(BuildContext context) {
    if (!_session.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session.error != null) {
      return Scaffold(
        body: ErrorState(
          'Não foi possível carregar seu acesso.\n${_session.error}\n\n'
          'Você já executou o supabase/schema.sql?',
          onRetry: _session.load,
        ),
      );
    }
    final user = _session.user;
    // Regra 9: funcionários inativos não acessam o sistema.
    if (user == null || !user.ativo) {
      return _PendingAccess(onLogout: _logout);
    }

    final path = _currentPath;
    final allowed = canAccess(user.perfil, path);
    final visible =
        _items.where((i) => canAccess(user.perfil, i.path)).toList();
    final title = _items.firstWhere((i) => i.path == path).label;
    final content = allowed ? widget.child : const AccessDenied();

    Widget sidebar(VoidCallback? afterTap) => _Sidebar(
          items: visible,
          selected: path,
          user: user,
          onLogout: _logout,
          onSelect: (p) {
            afterTap?.call();
            context.go(p);
          },
        );

    final wide = MediaQuery.of(context).size.width >= 960;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 270, child: sidebar(null)),
            const VerticalDivider(width: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: content,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      drawer: Drawer(
        backgroundColor: AppTheme.surface,
        child: SafeArea(child: sidebar(() => Navigator.of(context).pop())),
      ),
      body: Padding(padding: const EdgeInsets.all(12), child: content),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selected,
    required this.user,
    required this.onSelect,
    required this.onLogout,
  });

  final List<_NavItem> items;
  final String selected;
  final CurrentUser user;
  final ValueChanged<String> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: AppTheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Row(
              children: [
                Icon(Icons.sports_esports, color: scheme.tertiary, size: 30),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'FLIPERAMADA TI',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: ListTile(
                      dense: true,
                      leading: Icon(i.icon,
                          color: i.path == selected ? scheme.tertiary : null),
                      title: Text(i.label),
                      selected: i.path == selected,
                      selectedTileColor: scheme.primary.withAlpha(60),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onTap: () => onSelect(i.path),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.secondary,
              child: Text(user.nome.isEmpty ? '?' : user.nome[0].toUpperCase()),
            ),
            title: Text(user.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(user.perfilNome),
            trailing: IconButton(
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: onLogout,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingAccess extends StatelessWidget {
  const _PendingAccess({required this.onLogout});
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Panel(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_clock, size: 56),
                  const SizedBox(height: 16),
                  Text('Acesso pendente',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                    'Seu cadastro foi recebido, mas ainda não está ativo. '
                    'Peça a um administrador para liberar o seu acesso.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onLogout, child: const Text('Sair')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
