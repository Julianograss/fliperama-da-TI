import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/format.dart';
import '../../../shared/widgets/crud_page.dart';

const statusMaquina = {
  'ativa': 'Ativa',
  'em_manutencao': 'Em Manutenção',
  'inativa': 'Inativa',
};

class MachinesPage extends StatelessWidget {
  const MachinesPage({super.key});

  Future<void> _history(BuildContext context, Map<String, dynamic> m) async {
    final data = await Supabase.instance.client
        .from('movimentacoes_estoque')
        .select('*, produtos(nome), colaboradores(nome_completo)')
        .eq('maquina_id', m['id'])
        .eq('motivo', 'manutencao')
        .order('criado_em', ascending: false);
    final rows = List<Map<String, dynamic>>.from(data);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Manutenção - ${m['nome_jogo']}'),
        content: SizedBox(
          width: 520,
          child: rows.isEmpty
              ? const Text('Nenhuma peça retirada para esta máquina.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in rows)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.build_outlined),
                        title: Text(
                            '${(r['produtos'] as Map?)?['nome'] ?? '-'}  x${fmtNum(r['quantidade'])}'),
                        subtitle: Text(
                            '${fmtDateTime(r['criado_em'])} • ${(r['colaboradores'] as Map?)?['nome_completo'] ?? '-'}'
                            '${r['observacao'] != null ? '\n${r['observacao']}' : ''}'),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CrudPage(
      title: 'Máquinas Arcade',
      table: 'maquinas_arcade',
      orderBy: 'nome_jogo',
      ascending: true,
      activeKey: null,
      newLabel: 'Nova máquina',
      quickFilters: {
        for (final e in statusMaquina.entries)
          e.value: (r) => r['status'] == e.key,
      },
      rowActions: [
        RowAction(
          label: 'Histórico de manutenção',
          icon: Icons.history,
          onTap: (row) => _history(context, row),
        ),
      ],
      fields: const [
        FieldDef('nome_jogo', 'Nome do jogo', required: true),
        FieldDef('numero_patrimonio', 'Nº de patrimônio', required: true),
        FieldDef('data_aquisicao', 'Data de aquisição', type: FieldType.date),
        FieldDef('status', 'Status',
            type: FieldType.dropdown,
            required: true,
            defaultValue: 'ativa',
            options: statusMaquina),
      ],
    );
  }
}
