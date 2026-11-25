import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';

class _EntryLine {
  String? produtoId;
  final qtd = TextEditingController(text: '1');
  final custo = TextEditingController();

  double get total => toD(qtd.text) * toD(custo.text);

  void dispose() {
    qtd.dispose();
    custo.dispose();
  }
}

class EntriesPage extends StatefulWidget {
  const EntriesPage({super.key});

  @override
  State<EntriesPage> createState() => _EntriesPageState();
}

class _EntriesPageState extends State<EntriesPage> {
  SupabaseClient get _db => Supabase.instance.client;

  List<Map<String, dynamic>> _fornecedores = [];
  List<Map<String, dynamic>> _produtos = [];
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? _fornecedorId;
  DateTime _data = DateTime.now();
  final _obs = TextEditingController();
  final List<_EntryLine> _lines = [_EntryLine()];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _obs.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = await _db
          .from('fornecedores')
          .select('id, razao_social')
          .eq('ativo', true)
          .order('razao_social');
      final p = await _db
          .from('produtos')
          .select('id, nome, codigo_interno, preco_custo')
          .eq('ativo', true)
          .order('nome');
      final h = await _db
          .from('movimentacoes_estoque')
          .select(
              '*, produtos(nome), fornecedores(razao_social), colaboradores(nome_completo)')
          .eq('motivo', 'compra')
          .order('criado_em', ascending: false)
          .limit(30);
      _fornecedores = List<Map<String, dynamic>>.from(f);
      _produtos = List<Map<String, dynamic>>.from(p);
      _history = List<Map<String, dynamic>>.from(h);
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  double get _total => _lines.fold(0.0, (s, l) => s + l.total);

  Future<void> _submit() async {
    if (_fornecedorId == null) {
      showSnack(context, 'Selecione o fornecedor.', error: true);
      return;
    }
    for (final l in _lines) {
      if (l.produtoId == null || toD(l.qtd.text) <= 0 || l.custo.text.trim().isEmpty) {
        showSnack(context, 'Preencha produto, quantidade e custo de todos os itens.',
            error: true);
        return;
      }
    }
    final ok = await confirmDialog(
      context,
      title: 'Confirmar entrada',
      message:
          '${_lines.length} item(ns) • Total ${fmtMoney(_total)}\nO estoque será atualizado.',
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      await _db.rpc('registrar_entrada', params: {
        'p_fornecedor_id': _fornecedorId,
        'p_data': isoDate(_data),
        'p_observacao': _obs.text.trim().isEmpty ? null : _obs.text.trim(),
        'p_itens': [
          for (final l in _lines)
            {
              'produto_id': l.produtoId,
              'quantidade': toD(l.qtd.text),
              'custo_unitario': r2(toD(l.custo.text)),
            }
        ],
      });
      if (!mounted) return;
      showSnack(context, 'Entrada registrada e estoque atualizado.');
      for (final l in _lines) {
        l.dispose();
      }
      _lines
        ..clear()
        ..add(_EntryLine());
      _obs.clear();
      _fornecedorId = null;
      _data = DateTime.now();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(_error!, onRetry: _load);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle('Entradas de Mercadorias'),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: 320,
                      child: DropdownButtonFormField<String>(
                        value: _fornecedorId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Fornecedor'),
                        items: [
                          for (final f in _fornecedores)
                            DropdownMenuItem(
                              value: f['id'] as String,
                              child: Text('${f['razao_social']}'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _fornecedorId = v),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56)),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text('Data: ${fmtDate(isoDate(_data))}'),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _data,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (d != null) setState(() => _data = d);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Itens', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (var i = 0; i < _lines.length; i++) _lineRow(i),
                TextButton.icon(
                  onPressed: () => setState(() => _lines.add(_EntryLine())),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar item'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _obs,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Observações'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text('Total: ${fmtMoney(_total)}',
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(200, 48)),
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: const Text('Confirmar entrada'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Últimas entradas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Panel(
            padding: EdgeInsets.zero,
            child: _history.isEmpty
                ? const EmptyState('Nenhuma entrada registrada.')
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Data')),
                        DataColumn(label: Text('Produto')),
                        DataColumn(label: Text('Fornecedor')),
                        DataColumn(label: Text('Qtd.')),
                        DataColumn(label: Text('Custo unit.')),
                        DataColumn(label: Text('Responsável')),
                      ],
                      rows: [
                        for (final h in _history)
                          DataRow(cells: [
                            DataCell(Text(fmtDate(h['data_movimento']))),
                            DataCell(Text('${(h['produtos'] as Map?)?['nome'] ?? '-'}')),
                            DataCell(Text('${(h['fornecedores'] as Map?)?['razao_social'] ?? '-'}')),
                            DataCell(Text(fmtNum(h['quantidade']))),
                            DataCell(Text(fmtMoney(h['custo_unitario']))),
                            DataCell(Text('${(h['colaboradores'] as Map?)?['nome_completo'] ?? '-'}')),
                          ]),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(int i) {
    final l = _lines[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              value: l.produtoId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Produto'),
              items: [
                for (final p in _produtos)
                  DropdownMenuItem(
                    value: p['id'] as String,
                    child: Text('${p['nome']} (${p['codigo_interno']})'),
                  ),
              ],
              onChanged: (v) => setState(() {
                l.produtoId = v;
                if (l.custo.text.isEmpty) {
                  final p = _produtos.firstWhere((p) => p['id'] == v);
                  l.custo.text = '${p['preco_custo']}';
                }
              }),
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: l.qtd,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantidade'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            width: 140,
            child: TextField(
              controller: l.custo,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Custo unit.', prefixText: 'R\$ '),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(width: 110, child: Text(fmtMoney(l.total))),
          if (_lines.length > 1)
            IconButton(
              tooltip: 'Remover item',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() {
                _lines.removeAt(i).dispose();
              }),
            ),
        ],
      ),
    );
  }
}
