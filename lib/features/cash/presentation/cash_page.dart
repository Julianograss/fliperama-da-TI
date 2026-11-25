import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/user_session.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';

const _formas = {
  'dinheiro': 'Dinheiro',
  'pix': 'PIX',
  'debito': 'Débito',
  'credito': 'Crédito',
};

const _tipoMov = {
  'venda': 'Venda',
  'suprimento': 'Suprimento',
  'sangria': 'Sangria',
  'estorno': 'Estorno',
};

class CashPage extends StatefulWidget {
  const CashPage({super.key});

  @override
  State<CashPage> createState() => _CashPageState();
}

class _CashPageState extends State<CashPage> {
  SupabaseClient get _db => Supabase.instance.client;
  CurrentUser get _me => UserSession.instance.user!;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _abertos = [];
  Map<String, Map<String, dynamic>> _esperado = {};
  Map<String, List<Map<String, dynamic>>> _movs = {};
  List<Map<String, dynamic>> _fechados = [];

  final _valorInicial = TextEditingController();
  bool _abrindo = false;

  Map<String, dynamic>? get _meuCaixa {
    for (final c in _abertos) {
      if (c['colaborador_id'] == _me.id) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _valorInicial.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      const sel =
          '*, colaboradores!caixas_colaborador_id_fkey(nome_completo)';
      final ab = await _db
          .from('caixas')
          .select(sel)
          .eq('status', 'aberto')
          .order('aberto_em');
      _abertos = List<Map<String, dynamic>>.from(ab);

      _esperado = {};
      _movs = {};
      for (final c in _abertos) {
        final id = c['id'] as String;
        final esp = await _db.rpc('calcular_esperado_caixa', params: {'p_caixa_id': id});
        _esperado[id] = Map<String, dynamic>.from(esp as Map);
        final mv = await _db
            .from('movimentacoes_caixa')
            .select()
            .eq('caixa_id', id)
            .order('criado_em', ascending: false)
            .limit(15);
        _movs[id] = List<Map<String, dynamic>>.from(mv);
      }

      final fe = await _db
          .from('caixas')
          .select(sel)
          .eq('status', 'fechado')
          .order('fechado_em', ascending: false)
          .limit(30);
      _fechados = List<Map<String, dynamic>>.from(fe);
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _abrir() async {
    final v = toD(_valorInicial.text);
    if (_valorInicial.text.trim().isEmpty || v < 0) {
      showSnack(context, 'Informe o valor inicial do caixa.', error: true);
      return;
    }
    setState(() => _abrindo = true);
    try {
      await _db.rpc('abrir_caixa', params: {'p_valor_inicial': r2(v)});
      _valorInicial.clear();
      if (mounted) showSnack(context, 'Caixa aberto.');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
    if (mounted) setState(() => _abrindo = false);
  }

  Future<void> _movimentar(Map<String, dynamic> caixa, String tipo) async {
    final valor = TextEditingController();
    final just = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tipo == 'sangria' ? 'Sangria' : 'Suprimento'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: valor,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Valor (R\$)'),
                  validator: (v) => toD(v) <= 0 ? 'Informe um valor' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: just,
                  decoration: const InputDecoration(labelText: 'Justificativa'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obrigatória' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 40)),
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    final v = r2(toD(valor.text));
    final j = just.text.trim();
    valor.dispose();
    just.dispose();
    if (ok != true) return;
    if (!mounted) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Confirmar ${tipo == 'sangria' ? 'sangria' : 'suprimento'}',
      message: '${fmtMoney(v)}\n$j',
    );
    if (!confirmed) return;

    try {
      await _db.rpc('movimentar_caixa', params: {
        'p_tipo': tipo,
        'p_valor': v,
        'p_justificativa': j,
        'p_caixa_id': caixa['id'],
      });
      if (mounted) showSnack(context, 'Movimentação registrada.');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _fechar(Map<String, dynamic> caixa) async {
    final esp = _esperado[caixa['id']] ?? {};
    final ctrls = {for (final k in _formas.keys) k: TextEditingController()};
    final just = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          double diff(String k) => toD(ctrls[k]!.text) - toD(esp[k]);
          final divergente =
              _formas.keys.any((k) => r2(diff(k)).abs() > 0);
          final total = _formas.keys.fold(0.0, (s, k) => s + diff(k));
          return AlertDialog(
            title: const Text('Fechar caixa'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Informe os valores contados por forma de pagamento:'),
                    const SizedBox(height: 12),
                    for (final e in _formas.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: ctrls[e.key],
                                keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true),
                                decoration: InputDecoration(
                                  labelText: '${e.value} contado',
                                  helperText: 'Esperado: ${fmtMoney(esp[e.key])}',
                                  isDense: true,
                                ),
                                onChanged: (_) => setLocal(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Dif.: ${fmtMoney(diff(e.key))}',
                                style: TextStyle(
                                  color: r2(diff(e.key)) == 0
                                      ? Colors.greenAccent
                                      : Colors.orangeAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text('Diferença total: ${fmtMoney(total)}',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    if (divergente) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: just,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Justificativa da divergência (obrigatória)',
                        ),
                        onChanged: (_) => setLocal(() {}),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(130, 40)),
                onPressed: (divergente && just.text.trim().isEmpty)
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Fechar caixa'),
              ),
            ],
          );
        },
      ),
    );

    final contados = {for (final e in ctrls.entries) e.key: r2(toD(e.value.text))};
    final j = just.text.trim();
    for (final c in ctrls.values) {
      c.dispose();
    }
    just.dispose();
    if (ok != true || !mounted) return;

    try {
      final res = await _db.rpc('fechar_caixa', params: {
        'p_caixa_id': caixa['id'],
        'p_contados': contados,
        'p_justificativa': j.isEmpty ? null : j,
      });
      final dif = toD((res as Map)['diferenca']);
      if (mounted) {
        showSnack(context, 'Caixa fechado. Diferença: ${fmtMoney(dif)}');
      }
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(_error!, onRetry: _load);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageTitle('Controle de Caixa', actions: [
            IconButton(
                tooltip: 'Atualizar',
                onPressed: _load,
                icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 16),
          if (_meuCaixa == null) _openPanel(),
          for (final c in _abertos) ...[
            const SizedBox(height: 16),
            _caixaCard(c),
          ],
          const SizedBox(height: 24),
          Text('Fechamentos anteriores',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _history(),
        ],
      ),
    );
  }

  Widget _openPanel() => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Abrir caixa', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Operador: ${_me.nome}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _valorInicial,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Valor inicial (troco)', prefixText: 'R\$ '),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
                  onPressed: _abrindo ? null : _abrir,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Abrir caixa'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _caixaCard(Map<String, dynamic> c) {
    final id = c['id'] as String;
    final esp = _esperado[id] ?? {};
    final mine = c['colaborador_id'] == _me.id;
    final operador =
        (c['colaboradores'] as Map?)?['nome_completo']?.toString() ?? '-';
    final saldo = esp.values.fold(0.0, (s, v) => s + toD(v));
    final movs = _movs[id] ?? [];

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.point_of_sale,
                  color: Theme.of(context).colorScheme.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${mine ? 'Meu caixa' : 'Caixa de $operador'} • aberto em ${fmtDateTime(c['aberto_em'])}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(fmtMoney(saldo),
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 4),
          Text('Valor inicial: ${fmtMoney(c['valor_inicial'])}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _formas.entries)
                Chip(label: Text('${e.value}: ${fmtMoney(esp[e.key])}')),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _movimentar(c, 'suprimento'),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Suprimento'),
              ),
              Tooltip(
                message: _me.isGestor
                    ? ''
                    : 'Sangria exige gerente ou administrador',
                child: OutlinedButton.icon(
                  onPressed: _me.isGestor ? () => _movimentar(c, 'sangria') : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Sangria'),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => _fechar(c),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Fechar caixa'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Movimentações (${movs.length})'),
            children: [
              if (movs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Nenhuma movimentação ainda.'),
                ),
              for (final m in movs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    (m['tipo'] == 'venda' || m['tipo'] == 'suprimento')
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    color: (m['tipo'] == 'venda' || m['tipo'] == 'suprimento')
                        ? Colors.greenAccent
                        : Colors.redAccent,
                  ),
                  title: Text(
                      '${_tipoMov[m['tipo']] ?? m['tipo']} • ${_formas[m['forma_pagamento']] ?? m['forma_pagamento']}'),
                  subtitle: Text(
                      '${fmtDateTime(m['criado_em'])}${m['justificativa'] != null ? ' • ${m['justificativa']}' : ''}'),
                  trailing: Text(fmtMoney(m['valor'])),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _history() {
    if (_fechados.isEmpty) {
      return const Panel(child: EmptyState('Nenhum caixa fechado ainda.'));
    }
    return Panel(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Operador')),
            DataColumn(label: Text('Abertura')),
            DataColumn(label: Text('Fechamento')),
            DataColumn(label: Text('Valor inicial')),
            DataColumn(label: Text('Diferença')),
            DataColumn(label: Text('Justificativa')),
          ],
          rows: [
            for (final c in _fechados)
              DataRow(
                color: toD(c['diferenca']) != 0
                    ? WidgetStateProperty.all(Colors.orange.withAlpha(40))
                    : null,
                cells: [
                  DataCell(Text(
                      '${(c['colaboradores'] as Map?)?['nome_completo'] ?? '-'}')),
                  DataCell(Text(fmtDateTime(c['aberto_em']))),
                  DataCell(Text(fmtDateTime(c['fechado_em']))),
                  DataCell(Text(fmtMoney(c['valor_inicial']))),
                  DataCell(Text(fmtMoney(c['diferenca']))),
                  DataCell(Text('${c['justificativa_divergencia'] ?? '-'}')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
