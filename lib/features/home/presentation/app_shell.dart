import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

const _destinations = [
  _Destination('/', 'Dashboard', Icons.dashboard_outlined),
  _Destination('/estoque', 'Estoque', Icons.inventory_2_outlined),
  _Destination('/setores', 'Setores', Icons.apartment_outlined),
  _Destination('/compras', 'Compras', Icons.shopping_cart_outlined),
  _Destination('/vendas', 'Vendas', Icons.point_of_sale_outlined),
  _Destination('/financeiro', 'Financeiro', Icons.account_balance_outlined),
  _Destination('/rh', 'RH', Icons.groups_outlined),
];

/// Estrutura das telas logadas: menu lateral (desktop) ou gaveta (celular).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  int get _selectedIndex {
    final i = _destinations.indexWhere((d) =>
        d.path == location || (d.path != '/' && location.startsWith(d.path)));
    return i < 0 ? 0 : i;
  }

  Future<void> _logout() => AuthRepository.instance.signOut();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    final email = AuthRepository.instance.currentUser?.email ?? '';

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: true,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => context.go(_destinations[i].path),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('ERP',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sair'),
                    ),
                  ),
                ),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: child,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_destinations[_selectedIndex].label)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: const Text('ERP',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                subtitle: Text(email),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    for (final d in _destinations)
                      ListTile(
                        leading: Icon(d.icon),
                        title: Text(d.label),
                        selected: d == _destinations[_selectedIndex],
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(d.path);
                        },
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sair'),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
