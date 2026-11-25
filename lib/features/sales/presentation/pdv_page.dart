import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/user_session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';

const _formas = {
  'dinheiro': 'Dinheiro',
  'pix': 'PIX',
  'debito': 'Cartão de Débito',
  'credito': 'Cartão de Crédito',
  'combinado': 'Pagamento combinado',
};

const _formasReais = {
  'dinheiro': 'Dinheiro',
  'pix': 'PIX',
  'debito': 'Débito',
  'credito': 'Crédito',
};

class _CartLine {
  _CartLine(this.p, this.qty);
  final Map<String, dynamic> p;
  double qty;
  double get price => toD(p['preco_venda']);
  double get subtotal => r2(price * qty);
  double get stock => toD(p['quantidade_estoque']);
}

class PdvPage extends StatefulWidget {
  const PdvPage({super.key});

  @override
  State<PdvPage> createState() => _PdvPageState();
}

class _PdvPageState extends State<PdvPage> {
  SupabaseClient get _db => Supabase.instance.client;
  CurrentUser get _me => UserSession.instance.user!;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _sales = [];
  Map<String, dynamic>? _caixa;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final Map<String, _CartLine> _cart = {};
  final _search = TextEditingController();
  final _desconto = TextEditingController();
  final _recebido = TextEditingController();
  final Map<String, TextEditingController> _combo = {
    for (final k in _formasReais.keys) k: TextEditingController(),
  };
  String _forma = 'dinheiro';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _desconto.dispose();
    _recebido.dispose();
    for (final c in _combo.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prods = await _db
          .from('produtos')
          .select('id, nome, codigo_interno, categoria, preco_venda, quantidade_estoque')
          .eq('ativo', true)
          .order('nome');
      final cx = await _db
          .from('caixas')
          .select()
          .eq('colaborador_id', _me.id)
          .eq('status', 'aberto')
          .maybeSingle();
      _products = List<Map<String, dynamic>>.from(prods);
      _caixa = cx;

      var q = _db
          .from('vendas')
          .select('*, colaboradores!vendas_colaborador_id_fkey(nome_completo)');
      if (!_me.isGestor && cx != null) {
        q = q.eq('caixa_id', cx['id']);
      }
      final v = await q.order('criado_em', ascending: false).limit(30);
      _sales = List<Map<String, dynamic>>.from(v);
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  // ----- totais -----
  double get _subtotal => r2(_cart.values.fold(0.0, (s, l) => s + l.subtotal));
  double get _desc => r2(toD(_desconto.text));
  double get _total => r2(max(0.0, _subtotal - _desc));

  List<Map<String, dynamic>> _pagamentos() {
    if (_forma == 'combinado') {
      return [
        for (final e in _combo.entries)
          if (toD(e.value.text) > 0) {'forma': e.key, 'valor': r2(toD(e.value.text))}
      ];
    }
    if (_forma == 'dinheiro') {
      final r = _recebido.text.trim().isEmpty ? _total : r2(toD(_recebido.text));
      return [
        {'forma': 'dinheiro', 'valor': r}
      ];
    }
    return [
      {'forma': _forma, 'valor': _total}
    ];
  }

  double get _pago =>
      r2(_pagamentos().fold(0.0, (s, p) => s + (p['valor'] as double)));
  double get _dinheiroPago => r2(_pagamentos()
      .where((p) => p['forma'] == 'dinheiro')
      .fold(0.0, (s, p) => s + (p['valor'] as double)));
  double get _troco => r2(max(0.0, _pago - _total));

  bool get _podeFinalizar =>
      _caixa != null &&
      _cart.isNotEmpty &&
      !_saving &&
      _pago + 0.001 >= _total &&
      _troco <= _dinheiroPago + 0.001;

  void _add(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final line = _cart[id];
    final stock = toD(p['quantidade_estoque']);
    final next = (line?.qty ?? 0) + 1;
    if (next > stock) {
      showSnack(context, 'Estoque insuficiente para "${p['nome']}".', error: true);
      return;
    }
    setState(() {
      if (line == null) {
        _cart[id] = _CartLine(p, 1);
      } else {
        line.qty = next;
      }
    });
  }

  void _change(_CartLine l, double delta) {
    final next = l.qty + delta;
    if (next <= 0) {
      setState(() => _cart.remove(l.p['id']));
      return;
    }
    if (next > l.stock) {
      showSnack(context, 'Estoque insuficiente para "${l.p['nome']}".', error: true);
      return;
    }
    setState(() => l.qty = next);
  }

  Future<void> _finalize() async {
    final ok = await confirmDialog(
      context,
      title: 'Finalizar venda',
      message:
          'Total: ${fmtMoney(_total)}\nForma: ${_formas[_forma]}\nTroco: ${fmtMoney(_troco)}',
      confirmLabel: 'Finalizar',
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      final id = await _db.rpc('registrar_venda', params: {
        'p_itens': [
          for (final l in _cart.values)
            {'produto_id': l.p['id'], 'quantidade': l.qty}
        ],
        'p_desconto': _desc,
        'p_pagamentos': _pagamentos(),
      });
      final troco = _troco;
      final venda = await _db.from('vendas').select('numero').eq('id', id).single();
      _cart.clear();
      _desconto.clear();
      _recebido.clear();
      for (final c in _combo.values) {
        c.clear();
      }
      await _load();
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 48),
            title: Text('Venda #${venda['numero']} concluída'),
            content: Text('Troco: ${fmtMoney(troco)}'),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(110, 40)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Nova venda'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _cancelSale(Map<String, dynamic> v) async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar venda #${v['numero']}'),
        content: TextField(
          controller: motivo,
          decoration: const InputDecoration(labelText: 'Motivo do cancelamento'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(130, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar venda'),
          ),
        ],
      ),
    );
    final text = motivo.text.trim();
    motivo.dispose();
    if (ok != true) return;
    try {
      await _db.rpc('cancelar_venda', params: {
        'p_venda_id': v['id'],
        'p_motivo': text,
      });
      if (mounted) showSnack(context, 'Venda cancelada e estoque devolvido.');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(_error!, onRetry: _load);

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle('PDV / Vendas'),
          const TabBar(tabs: [
            Tab(text: 'Nova venda'),
            Tab(text: 'Vendas recentes'),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(children: [_saleTab(), _salesTab()]),
          ),
        ],
      ),
    );
  }

  // ----- aba de venda -----
  Widget _saleTab() {
    if (_caixa == null) {
      return Center(
        child: Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              const Text('Abra o seu caixa para começar a vender.'),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
                onPressed: () => context.go('/caixa'),
                child: const Text('Ir para o Caixa'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final catalog = _catalog();
      final cart = _cartPanel();
      if (c.maxWidth >= 900) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: catalog),
            const SizedBox(width: 16),
            SizedBox(width: 400, child: cart),
          ],
        );
      }
      return SingleChildScrollView(
        child: Column(children: [
          SizedBox(height: 380, child: catalog),
          const SizedBox(height: 12),
          cart,
        ]),
      );
    });
  }

  Widget _catalog() {
    final q = _search.text.trim().toLowerCase();
    final list = _products.where((p) {
      if (q.isEmpty) return true;
      return '${p['nome']}'.toLowerCase().contains(q) ||
          '${p['codigo_interno']}'.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            hintText: 'Pesquisar produto por nome ou código...',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: list.isEmpty
              ? const EmptyState('Nenhum produto encontrado.')
              : GridView.extent(
                  maxCrossAxisExtent: 190,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.25,
                  children: [
                    for (final p in list)
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: toD(p['quantidade_estoque']) <= 0
                            ? null
                            : () => _add(p),
                        child: Opacity(
                          opacity: toD(p['quantidade_estoque']) <= 0 ? 0.4 : 1,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text('${p['nome']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ),
                                Text(fmtMoney(p['preco_venda']),
                                    style: TextStyle(
                                        color:
                                            Theme.of(context).colorScheme.tertiary,
                                        fontWeight: FontWeight.bold)),
                                Text('Estoque: ${fmtNum(p['quantidade_estoque'])}',
                                    style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _cartPanel() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Carrinho', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_cart.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Toque em um produto para adicionar.')),
            )
          else
            for (final l in _cart.values)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${l.p['nome']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${fmtMoney(l.price)} • ${fmtMoney(l.subtotal)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => _change(l, -1)),
                    Text(fmtNum(l.qty)),
                    IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _change(l, 1)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _cart.remove(l.p['id']))),
                  ],
                ),
              ),
          const Divider(),
          _row('Subtotal', fmtMoney(_subtotal)),
          const SizedBox(height: 8),
          TextField(
            controller: _desconto,
            enabled: _me.isGestor,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Desconto (R\$)',
              isDense: true,
              helperText:
                  _me.isGestor ? null : 'Somente gerente ou administrador',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _row('TOTAL', fmtMoney(_total), big: true),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _formas.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _forma == e.key,
                  onSelected: (_) => setState(() => _forma = e.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_forma == 'dinheiro')
            TextField(
              controller: _recebido,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Valor recebido (R\$)', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          if (_forma == 'combinado')
            for (final e in _formasReais.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _combo[e.key],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: '${e.value} (R\$)', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
          const SizedBox(height: 4),
          _row('Troco', fmtMoney(_troco)),
          if (_forma == 'combinado' && _pago + 0.001 < _total)
            Text('Faltam ${fmtMoney(_total - _pago)}',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _podeFinalizar ? _finalize : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Finalizar venda'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool big = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: big ? Theme.of(context).textTheme.titleLarge : null),
          Text(value,
              style: big ? Theme.of(context).textTheme.titleLarge : null),
        ],
      );

  // ----- aba de vendas recentes -----
  Widget _salesTab() {
    if (_sales.isEmpty) return const EmptyState('Nenhuma venda registrada.');
    return Panel(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        itemCount: _sales.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final v = _sales[i];
          final cancelada = v['status'] == 'cancelada';
          return ListTile(
            leading: Icon(
              cancelada ? Icons.cancel_outlined : Icons.receipt_long_outlined,
              color: cancelada ? Colors.redAccent : Colors.greenAccent,
            ),
            title: Text(
              'Venda #${v['numero']} • ${fmtMoney(v['total'])}',
              style: TextStyle(
                  decoration: cancelada ? TextDecoration.lineThrough : null),
            ),
            subtitle: Text(
              '${fmtDateTime(v['criado_em'])} • '
              '${(v['colaboradores'] as Map?)?['nome_completo'] ?? '-'}'
              '${cancelada ? '\nCancelada: ${v['motivo_cancelamento']}' : ''}',
            ),
            trailing: (!cancelada && _me.isGestor)
                ? TextButton(
                    onPressed: () => _cancelSale(v),
                    child: const Text('Cancelar'),
                  )
                : null,
          );
        },
      ),
    );
  }
}
