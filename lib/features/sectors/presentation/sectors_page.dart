import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SectorsPage extends StatefulWidget {
  const SectorsPage({super.key});

  @override
  State<SectorsPage> createState() => _SectorsPageState();
}

class _SectorsPageState extends State<SectorsPage> {
  SupabaseClient get _db => Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await _db.from('sectors').select().order('name');
    return List<Map<String, dynamic>>.from(data);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _addSector() async {
    final name = TextEditingController();
    final description = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo setor'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
            ],
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
    );

    if (ok != true || name.text.trim().isEmpty) return;

    try {
      await _db.from('sectors').insert({
        'name': name.text.trim(),
        'description': description.text.trim(),
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
              child: Text('Setores',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _addSector,
              icon: const Icon(Icons.add),
              label: const Text('Novo setor'),
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
                return const Center(child: Text('Nenhum setor cadastrado.'));
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = items[i];
                  return ListTile(
                    leading: const Icon(Icons.apartment_outlined),
                    title: Text('${s['name']}'),
                    subtitle: Text('${s['description'] ?? ''}'),
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
