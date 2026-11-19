import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  SupabaseClient get _db => Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final data =
        await _db.from('products').select('*, sectors(name)').order('name');
    return List<Map<String, dynamic>>.from(data);
  }

  void _reload() => setState(() => _future = _load());

  num _num(String text) => num.tryParse(text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _addProduct() async {
    final sku = TextEditingController();
    final name = TextEditingController();
    final quantity = TextEditingController(text: '0');
    final minQuantity = TextEditingController(text: '0');
    final price = TextEditingController(text: '0');

    final sectors = List<Map<String, dynamic>>.from(
        await _db.from('sectors').select('id, name').order('name'));
    if (!mounted) return;

    String? sectorId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Novo produto'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: sku,
                    decoration: const InputDecoration(labelText: 'Código (SKU)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nome'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: sectorId,
                    decoration: const InputDecoration(labelText: 'Setor'),
                    items: [
                      for (final s in sectors)
                        DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text('${s['name']}'),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => sectorId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Quantidade inicial'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: minQuantity,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Estoque mínimo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Preço (R\$)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || name.text.trim().isEmpty || sku.text.trim().isEmpty) {
      return;
    }

    try {
      await _db.from('products').insert({
        'sku': sku.text.trim(),
        'name': name.text.trim(),
        'sector_id': sectorId,
        'quantity': _num(quantity.text),
        'min_quantity': _num(minQuantity.text),
        'price': _num(price.text),
      });
      _reload();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Estoque',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _addProduct,
              icon: const Icon(Icons.add),
              label: const Text('Novo produto'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}'));
              }
              final items = snap.data!;
              if (items.isEmpty) {
                return const Center(child: Text('Nenhum produto cadastrado.'));
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = items[i];
                  final q = (p['quantity'] as num?) ?? 0;
                  final m = (p['min_quantity'] as num?) ?? 0;
                  final low = q <= m;
                  final sector =
                      (p['sectors'] as Map<String, dynamic>?)?['name'] ?? '-';
                  return ListTile(
                    leading: Icon(
                      low ? Icons.warning_amber : Icons.inventory_2_outlined,
                      color: low ? Colors.orange : null,
                    ),
                    title: Text('${p['name']}'),
                    subtitle: Text('SKU ${p['sku']} • Setor: $sector'),
                    trailing: Text(
                      '$q un.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
