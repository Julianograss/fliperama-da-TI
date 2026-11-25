import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/user_session.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';

const _motivos = {
  'manutencao': 'Retirada para manutenção',
  'perda': 'Perda',
  'vencido': 'Produto vencido',
  'danificado': 'Produto danificado',
  'ajuste': 'Ajuste manual de estoque',
  'venda': 'Venda (PDV)',
  'estorno': 'Estorno',
};

class ExitsPage extends StatefulWidget {
  const ExitsPage({super.key});

  @override
  State<ExitsPage> createState() => _ExitsPageState();
}

class _ExitsPageState extends State<ExitsPage> {
  SupabaseClient get _db => Supabase.instance.client;

  List<Map<String, dynamic>> _produtos = [];
  List<Map<String, dynamic>> _maquinas = [];
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? _produtoId;
  String? _motivo;
  String? _maquinaId;
  final _qtd = TextEditingController(text: '1');
  final _obs = TextEditingController();

  bool get _gestor => UserSession.instance.user?.isGestor ?? false;

  Map<String, String> get _motivosPermitidos => _gestor
      ? {
          for (final k in ['manutencao', 'perda', 'vencido', 'danificado', 'ajuste'])
            k: _motivos[k]!
        }
      : {'manutencao': _motivos['manutencao']!};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qtd.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _db
          .from('produtos')
          .select('id, nome, codigo_interno, quantidade_estoque, categoria')
          .eq('ativo', true)
          .order('nome');
      final m = await _db
          .from('maquinas_arcade')
          .select('id, nome_jogo, numero_patrimonio, status')
          .neq('status', 'inativa')
          .order('nome_jogo');
      final h = await _db
          .from('movimentacoes_estoque')
          .select(
              '*, produtos(nome), maquinas_arcade(nome_jogo), colaboradores(nome_completo)')
          .eq('tipo', 'saida')
          .order('criado_em', ascending: false)
          .limit(50);
      _produtos = List<Map<String, dynamic>>.from(p);
      _maquinas = List<Map<String, dynamic>>.from(m);
      _history = List<Map<String, dynamic>>.from(h);
      if (_motivo == null && _motivosPermitidos.length == 1) {
        _motivo = _motivosPermitidos.keys.first;
      }
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submit() async {
    final qtd = toD(_qtd.text);
    if (_produtoId == null || _motivo == null || qtd <= 0) {
      showSnack(context, 'Informe produto, motivo e quantidade.', error: true);
      return;
    }
    if (_motivo == 'manutencao' && _maquinaId == null) {
      showSnack(context, 'Selecione a máquina para saídas de manutenção.',
          error: true);
      return;
    }
    final produto = _produtos.firstWhere((p) => p['id'] == _produtoId);
    final ok = await confirmDialog(
      context,
      title: 'Confirmar saída',
      message:
          '${_motivos[_motivo]}\n${produto['nome']} x ${fmtNum(qtd)}\nO estoque será reduzido.',
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      await _db.rpc('registrar_saida', params: {
        'p_produto_id': _produtoId,
        'p_quantidade': qtd,
        'p_motivo': _motivo,
        'p_maquina_id': _motivo == 'manutencao' ? _maquinaId : null,
        'p_observacao': _obs.text.trim().isEmpty ? null : _obs.text.trim(),
      });
      if (!mounted) return;
      showSnack(context, 'Saída registrada.');
      _qtd.text = '1';
      _obs.clear();
      _produtoId = null;
      _maquinaId = null;
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

    final permitidos = _motivosPermitidos;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle('Saídas de Estoque'),
          const SizedBox(height: 8),
          const Text(
            'Saídas por venda são geradas automaticamente pelo PDV. '
            'Perdas, vencidos, danificados e ajustes exigem gerente ou administrador.',
          ),
          const SizedBox(height: 16),
          Panel(
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String>(
                    value: _produtoId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Produto'),
                    items: [
                      for (final p in _produtos)
                        DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(
                              '${p['nome']} (estoque: ${fmtNum(p['quantidade_estoque'])})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _produtoId = v),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _qtd,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantidade'),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    value: _motivo,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Motivo'),
                    items: [
                      for (final e in permitidos.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => _motivo = v),
                  ),
                ),
                if (_motivo == 'manutencao')
                  SizedBox(
                    width: 300,
                    child: DropdownButtonFormField<String>(
                      value: _maquinaId,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Máquina (obrigatória)'),
                      items: [
                        for (final m in _maquinas)
                          DropdownMenuItem(
                            value: m['id'] as String,
                            child: Text(
                                '${m['nome_jogo']} (${m['numero_patrimonio']})'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _maquinaId = v),
                    ),
                  ),
                SizedBox(
                  width: 420,
                  child: TextField(
                    controller: _obs,
                    decoration: const InputDecoration(labelText: 'Observação'),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('Registrar saída'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Histórico de saídas',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Panel(
            padding: EdgeInsets.zero,
            child: _history.isEmpty
                ? const EmptyState('Nenhuma saída registrada.')
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Data/hora')),
                        DataColumn(label: Text('Produto')),
                        DataColumn(label: Text('Qtd.')),
                        DataColumn(label: Text('Motivo')),
                        DataColumn(label: Text('Máquina')),
                        DataColumn(label: Text('Responsável')),
                      ],
                      rows: [
                        for (final h in _history)
                          DataRow(cells: [
                            DataCell(Text(fmtDateTime(h['criado_em']))),
                            DataCell(Text('${(h['produtos'] as Map?)?['nome'] ?? '-'}')),
                            DataCell(Text(fmtNum(h['quantidade']))),
                            DataCell(Text(_motivos['${h['motivo']}'] ?? '${h['motivo']}')),
                            DataCell(Text('${(h['maquinas_arcade'] as Map?)?['nome_jogo'] ?? '-'}')),
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
}
