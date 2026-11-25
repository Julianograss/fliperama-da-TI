import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/simple_charts.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _dias = 7;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final res = await Supabase.instance.client
        .rpc('dashboard_resumo', params: {'p_dias': _dias});
    return Map<String, dynamic>.from(res as Map);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorState(
            'Não foi possível carregar o dashboard.\n${errorMessage(snap.error!)}',
            onRetry: _reload,
          );
        }
        final d = snap.data!;
        final gestor = d.containsKey('faturamento_dia');
        final scheme = Theme.of(context).colorScheme;

        final cards = <_Stat>[
          if (gestor) ...[
            _Stat('Faturamento do dia', fmtMoney(d['faturamento_dia']),
                Icons.attach_money, Colors.greenAccent),
            _Stat('Total de vendas (hoje)', fmtNum(d['total_vendas']),
                Icons.receipt_outlined, scheme.primary),
          ],
          _Stat('Produtos cadastrados', fmtNum(d['produtos_cadastrados']),
              Icons.inventory_2_outlined, scheme.tertiary),
          _Stat('Estoque baixo', fmtNum(d['estoque_baixo']),
              Icons.warning_amber_outlined, Colors.orangeAccent),
          _Stat('Máquinas ativas', fmtNum(d['maquinas_ativas']),
              Icons.sports_esports_outlined, scheme.secondary),
          _Stat('Máquinas em manutenção', fmtNum(d['maquinas_manutencao']),
              Icons.build_outlined, Colors.amber),
          if (gestor) ...[
            _Stat('Caixa atual', fmtMoney(d['caixa_atual']),
                Icons.account_balance_wallet_outlined, scheme.tertiary),
            _Stat('Despesas pendentes', fmtMoney(d['despesas_pendentes']),
                Icons.money_off_outlined, Colors.redAccent),
          ],
        ];

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageTitle('Dashboard', actions: [
                if (gestor)
                  DropdownButton<int>(
                    value: _dias,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('Últimos 7 dias')),
                      DropdownMenuItem(value: 15, child: Text('Últimos 15 dias')),
                      DropdownMenuItem(value: 30, child: Text('Últimos 30 dias')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      _dias = v;
                      _reload();
                    },
                  ),
                IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh)),
              ]),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [for (final c in cards) _StatCard(c)],
              ),
              if (gestor) ...[
                const SizedBox(height: 24),
                _charts(d, scheme),
                const SizedBox(height: 24),
                _latest(d),
              ] else ...[
                const SizedBox(height: 24),
                const Panel(
                  child: Text(
                    'Os indicadores financeiros e gráficos são exibidos para '
                    'gerentes e administradores.',
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _list(dynamic v) =>
      List<Map<String, dynamic>>.from((v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));

  Widget _charts(Map<String, dynamic> d, ColorScheme scheme) {
    final fat = _list(d['faturamento_periodo']);
    final cat = _list(d['vendas_categoria']);
    final es = _list(d['entradas_saidas']);

    final fatPanel = _chartPanel(
      'Faturamento por período',
      SimpleBarChart(
        labels: [for (final r in fat) fmtShortDay(r['dia'])],
        values: [for (final r in fat) toD(r['valor'])],
        color: scheme.primary,
        format: fmtMoney,
      ),
    );
    final catPanel = _chartPanel(
      'Vendas por categoria',
      cat.isEmpty
          ? const EmptyState('Sem vendas no período.')
          : HBarList(
              labels: [for (final r in cat) '${r['categoria']}'],
              values: [for (final r in cat) toD(r['valor'])],
              color: scheme.secondary,
              format: fmtMoney,
            ),
    );
    final esPanel = _chartPanel(
      'Entradas e saídas financeiras',
      Column(children: [
        DualBarChart(
          labels: [for (final r in es) fmtShortDay(r['dia'])],
          a: [for (final r in es) toD(r['entradas'])],
          b: [for (final r in es) toD(r['saidas'])],
          colorA: Colors.greenAccent,
          colorB: Colors.redAccent,
          format: fmtMoney,
        ),
        const SizedBox(height: 8),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.circle, size: 10, color: Colors.greenAccent),
          SizedBox(width: 4),
          Text('Entradas'),
          SizedBox(width: 16),
          Icon(Icons.circle, size: 10, color: Colors.redAccent),
          SizedBox(width: 4),
          Text('Saídas'),
        ]),
      ]),
    );

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: fatPanel),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: catPanel),
          ]),
          const SizedBox(height: 16),
          esPanel,
        ]);
      }
      return Column(children: [
        fatPanel,
        const SizedBox(height: 16),
        catPanel,
        const SizedBox(height: 16),
        esPanel,
      ]);
    });
  }

  Widget _chartPanel(String title, Widget child) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );

  Widget _latest(Map<String, dynamic> d) {
    final items = _list(d['ultimas_movimentacoes']);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Últimas movimentações',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const EmptyState('Nenhuma movimentação registrada ainda.')
          else
            for (final m in items)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch ('${m['tipo']}') {
                  'Venda' => Icons.shopping_bag_outlined,
                  'Estoque' => Icons.inventory_2_outlined,
                  _ => Icons.account_balance_wallet_outlined,
                }),
                title: Text('${m['descricao']}'),
                subtitle: Text(fmtDateTime(m['em'])),
                trailing: m['valor'] == null ? null : Text(fmtMoney(m['valor'])),
              ),
        ],
      ),
    );
  }
}

class _Stat {
  _Stat(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.s);
  final _Stat s;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppTheme.card,
          border: Border.all(color: s.color.withAlpha(90)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: s.color.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(s.icon, color: s.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.value,
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis),
                  Text(s.label,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
