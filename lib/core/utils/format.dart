import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _2(int n) => n.toString().padLeft(2, '0');

double toD(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse('$v'.trim().replaceAll(',', '.')) ?? 0;
}

/// Arredonda para 2 casas (evita 12.299999999 em valores monetários).
double r2(double v) => double.parse(v.toStringAsFixed(2));

String fmtNum(dynamic v) {
  final d = toD(v);
  if (d == d.roundToDouble()) return d.toInt().toString();
  var s = d.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

String fmtMoney(dynamic v) {
  final value = toD(v);
  final neg = value < 0;
  final parts = value.abs().toStringAsFixed(2).split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}R\$ $buf,${parts[1]}';
}

String fmtDate(dynamic v) {
  if (v == null) return '-';
  final s = '$v';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  final l = s.length > 10 ? d.toLocal() : d;
  return '${_2(l.day)}/${_2(l.month)}/${l.year}';
}

String fmtDateTime(dynamic v) {
  if (v == null) return '-';
  final s = '$v';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  final l = d.toLocal();
  return '${_2(l.day)}/${_2(l.month)}/${l.year} ${_2(l.hour)}:${_2(l.minute)}';
}

String fmtShortDay(dynamic v) {
  final d = DateTime.tryParse('$v');
  if (d == null) return '$v';
  return '${_2(d.day)}/${_2(d.month)}';
}

String isoDate(DateTime d) => '${d.year}-${_2(d.month)}-${_2(d.day)}';

/// Converte erros do Supabase em mensagens amigáveis.
String errorMessage(Object e) {
  var msg = e.toString();
  if (e is PostgrestException) {
    msg = e.message;
  } else if (e is AuthException) {
    msg = e.message;
  }
  final lower = msg.toLowerCase();
  if (lower.contains('produtos_estoque_nao_negativo')) {
    return 'Estoque insuficiente para esta operação.';
  }
  if (lower.contains('duplicate key')) {
    return 'Já existe um registro com esse valor (código, CPF/CNPJ ou patrimônio).';
  }
  if (lower.contains('row-level security')) {
    return 'Você não tem permissão para esta operação.';
  }
  return msg;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? scheme.error : Colors.green.shade700,
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(110, 40)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}
