import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/user_session.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/simple_charts.dart';

const _tipos = {
  'vendas': 'Vendas por período',
  'mais_vendidos': 'Produtos mais vendidos',
  'mov_estoque': 'Movimentações de estoque',
  'entradas_saidas': 'Entradas e saídas (financeiro)',
  'fluxo_caixa': 'Fluxo de caixa',
  'despesas': 'Despesas',
  'fechamentos': 'Fechamentos de caixa',
  'historico_manutencao': 'Histórico de manutenção',
};

const _moneyKeys = {
  'total', 'descontos', 'entradas', 'saidas', 'saldo', 'valor', 'valor_inicial',
  'diferenca', 'vendas_caixa', 'suprimentos', 'sangrias', 'estornos',
};

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String _tipo = 'vendas';
  DateTime _ini = DateTime.now().subtract(const Duration(days: 29));
  DateTime _fim = DateTime.now();
  List<Map<String, dynamic>>? _rows;
  bool _loading = false;
  String? _error;

  Map<String, String> get _tiposPermitidos {
    final gestor = UserSession.instance.user?.isGestor ?? false;
    if (gestor) return _tipos;
    return {'historico_manutencao': _tipos['historico_manutencao']!};
  }

  @override
  void initState() {
    super.initState();
    _tipo = _tiposPermitidos.keys.first;
  }

  Future<void> _pick(bool start) async {
    final d = await showDatePicker(
      context: context,
      initialDate: start ? _ini : _fim,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => start ? _ini = d : _fim = d);
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc('relatorio', params: {
        'p_tipo': _tipo,
        'p_inicio': isoDate(_ini),
        'p_fim': isoDate(_fim),
      });
      _rows = List<Map<String, dynamic>>.from(
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (e) {
      _error = errorMessage(e);
      _rows = null;
    }
    if (mounted) setState(() => _loading = false);
  }

  String _fmt(String k, dynamic v) {
    if (v == null) return '-';
    if (v is num) return _moneyKeys.contains(k) ? fmtMoney(v) : fmtNum(v);
    final s = '$v';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) return fmtDateTime(s);
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return fmtDate(s);
    return s;
  }

  String _header(String k) {
    final t = k.replaceAll('_', ' ');
    return t[0].toUpperCase() + t.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle('Relatórios'),
          const SizedBox(height: 16),
          Panel(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String>(
                    value: _tipo,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Relatório'),
                    items: [
                      for (final e in _tiposPermitidos.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() {
                      _tipo = v!;
                      _rows = null;
                    }),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('De ${fmtDate(isoDate(_ini))}'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('Até ${fmtDate(isoDate(_fim))}'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(150, 52)),
                  onPressed: _loading ? null : _run,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Gerar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            ErrorState(_error!, onRetry: _run)
          else if (_rows == null)
            const EmptyState('Escolha o relatório e o período, depois toque em Gerar.',
                icon: Icons.bar_chart_outlined)
          else if (_rows!.isEmpty)
            const EmptyState('Nenhum dado no período selecionado.')
          else ...[
            _chart(context),
            _table(),
          ],
        ],
      ),
    );
  }

  Widget _chart(BuildContext context) {
    final rows = _rows!;
    if (rows.length < 2 || rows.length > 31) return const SizedBox.shrink();
    final keys = rows.first.keys.toList();
    String? valueKey;
    for (final k in keys.skip(1)) {
      if (rows.first[k] is num) {
        valueKey = k;
        break;
      }
    }
    if (valueKey == null) return const SizedBox.shrink();
    final vk = valueKey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_header(vk), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SimpleBarChart(
              labels: [for (final r in rows) _fmt(keys.first, r[keys.first]).split(' ').first],
              values: [for (final r in rows) toD(r[vk])],
              color: Theme.of(context).colorScheme.primary,
              format: (v) => _moneyKeys.contains(vk) ? fmtMoney(v) : fmtNum(v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table() {
    final rows = _rows!;
    final keys = rows.first.keys.toList();
    return Panel(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [for (final k in keys) DataColumn(label: Text(_header(k)))],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                for (final k in keys) DataCell(Text(_fmt(k, r[k]))),
              ]),
          ],
        ),
      ),
    );
  }
}
