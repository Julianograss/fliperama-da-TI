import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, int>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, int>> _load() async {
    final db = Supabase.instance.client;
    final products = await db.from('products').select('quantity, min_quantity');
    final sectors = await db.from('sectors').select('id');

    final low = products.where((p) {
      final q = (p['quantity'] as num?) ?? 0;
      final m = (p['min_quantity'] as num?) ?? 0;
      return q <= m;
    }).length;

    return {
      'products': products.length,
      'sectors': sectors.length,
      'low': low,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text(
              'Não foi possível carregar os dados.\n'
              'Você já executou o supabase/schema.sql?\n\n${snap.error}',
              textAlign: TextAlign.center,
            ),
          );
        }
        final data = snap.data!;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _StatCard(
                    label: 'Produtos',
                    value: '${data['products']}',
                    icon: Icons.inventory_2_outlined,
                  ),
                  _StatCard(
                    label: 'Setores',
                    value: '${data['sectors']}',
                    icon: Icons.apartment_outlined,
                  ),
                  _StatCard(
                    label: 'Estoque baixo',
                    value: '${data['low']}',
                    icon: Icons.warning_amber_outlined,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 36, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: theme.textTheme.headlineMedium),
                  Text(label),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
