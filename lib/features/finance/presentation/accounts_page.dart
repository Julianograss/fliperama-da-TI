import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/format.dart';
import '../../../shared/widgets/crud_page.dart';

String _statusExibicao(Map<String, dynamic> r) {
  final status = '${r['status']}';
  if (status == 'pendente') {
    final venc = DateTime.tryParse('${r['data_vencimento']}');
    final hoje = DateTime.now();
    if (venc != null &&
        venc.isBefore(DateTime(hoje.year, hoje.month, hoje.day))) {
      return 'atrasado';
    }
  }
  return status;
}

const _statusLabel = {
  'pendente': 'Pendente',
  'pago': 'Pago',
  'atrasado': 'Atrasado',
  'cancelado': 'Cancelado',
};

bool _aberta(Map<String, dynamic> r) {
  final s = _statusExibicao(r);
  return s == 'pendente' || s == 'atrasado';
}

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  SupabaseClient get _db => Supabase.instance.client;

  Future<void> _settle(BuildContext context, Map<String, dynamic> r) async {
    final receber = r['tipo'] == 'receber';
    final ok = await confirmDialog(
      context,
      title: receber ? 'Registrar recebimento' : 'Registrar pagamento',
      message: '${r['descricao']}\nValor: ${fmtMoney(r['valor'])}',
    );
    if (!ok) return;
    await _db.from('contas_financeiras').update({
      'status': 'pago',
      'data_pagamento': isoDate(DateTime.now()),
    }).eq('id', r['id']);
    if (context.mounted) {
      showSnack(context,
          receber ? 'Recebimento registrado.' : 'Pagamento registrado.');
    }
  }

  Future<void> _cancel(BuildContext context, Map<String, dynamic> r) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancelar conta',
      message:
          'Cancelar "${r['descricao']}"? O registro será mantido como cancelado.',
    );
    if (!ok) return;
    await _db
        .from('contas_financeiras')
        .update({'status': 'cancelado'}).eq('id', r['id']);
  }

  @override
  Widget build(BuildContext context) {
    return CrudPage(
      title: 'Contas a Pagar e Receber',
      table: 'contas_financeiras',
      orderBy: 'data_vencimento',
      ascending: true,
      activeKey: null,
      newLabel: 'Nova conta',
      select: '*, fornecedores(razao_social)',
      rowHighlight: (r) => _statusExibicao(r) == 'atrasado',
      rowEditable: _aberta,
      quickFilters: {
        'A pagar': (r) => r['tipo'] == 'pagar',
        'A receber': (r) => r['tipo'] == 'receber',
        'Pendentes': (r) => _statusExibicao(r) == 'pendente',
        'Atrasadas': (r) => _statusExibicao(r) == 'atrasado',
        'Pagas': (r) => r['status'] == 'pago',
      },
      rowActions: [
        RowAction(
          label: 'Registrar pagamento/recebimento',
          icon: Icons.check_circle_outline,
          visible: _aberta,
          onTap: (r) => _settle(context, r),
        ),
        RowAction(
          label: 'Cancelar',
          icon: Icons.cancel_outlined,
          visible: _aberta,
          onTap: (r) => _cancel(context, r),
        ),
      ],
      fields: [
        const FieldDef('descricao', 'Descrição', required: true),
        const FieldDef('categoria', 'Categoria', required: true),
        const FieldDef('tipo', 'Tipo',
            type: FieldType.dropdown,
            required: true,
            options: {'pagar': 'A pagar', 'receber': 'A receber'}),
        const FieldDef('valor', 'Valor', type: FieldType.money, required: true),
        const FieldDef('data_vencimento', 'Vencimento',
            type: FieldType.date, required: true),
        FieldDef('fornecedor_id', 'Fornecedor',
            type: FieldType.lookup,
            lookupTable: 'fornecedores',
            lookupLabel: 'razao_social',
            display: (r) =>
                (r['fornecedores'] as Map?)?['razao_social']?.toString() ?? '-'),
        FieldDef('status', 'Status',
            inForm: false,
            display: (r) =>
                _statusLabel[_statusExibicao(r)] ?? '${r['status']}'),
        const FieldDef('data_pagamento', 'Data do pagamento',
            type: FieldType.date, inForm: false),
      ],
    );
  }
}
