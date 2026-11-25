import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/format.dart';
import 'common.dart';

enum FieldType { text, multiline, number, money, date, dropdown, lookup, email, phone }

class FieldDef {
  const FieldDef(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.options,
    this.lookupTable,
    this.lookupLabel,
    this.inTable = true,
    this.inForm = true,
    this.createOnly = false,
    this.defaultValue,
    this.display,
  });

  final String key;
  final String label;
  final FieldType type;
  final bool required;

  /// Para dropdown: valor -> rótulo.
  final Map<String, String>? options;

  /// Para lookup: tabela e coluna exibida (a tabela precisa ter `ativo`).
  final String? lookupTable;
  final String? lookupLabel;

  final bool inTable;
  final bool inForm;
  final bool createOnly;
  final dynamic defaultValue;
  final String Function(Map<String, dynamic> row)? display;
}

class RowAction {
  const RowAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.visible,
  });

  final String label;
  final IconData icon;
  final Future<void> Function(Map<String, dynamic> row) onTap;
  final bool Function(Map<String, dynamic> row)? visible;
}

/// Tela genérica de cadastro: listagem, busca, filtros, criar, editar e inativar.
class CrudPage extends StatefulWidget {
  const CrudPage({
    super.key,
    required this.title,
    required this.table,
    required this.fields,
    this.select = '*',
    this.orderBy = 'criado_em',
    this.ascending = false,
    this.canCreate = true,
    this.canEdit = true,
    this.activeKey = 'ativo',
    this.showInactiveDefault = false,
    this.quickFilters = const {},
    this.rowHighlight,
    this.rowEditable,
    this.rowActions = const [],
    this.banner,
    this.newLabel = 'Novo',
    this.showTitle = true,
  });

  final String title;
  final String table;
  final List<FieldDef> fields;
  final String select;
  final String orderBy;
  final bool ascending;
  final bool canCreate;
  final bool canEdit;
  final String? activeKey;
  final bool showInactiveDefault;
  final Map<String, bool Function(Map<String, dynamic> row)> quickFilters;
  final bool Function(Map<String, dynamic> row)? rowHighlight;
  final bool Function(Map<String, dynamic> row)? rowEditable;
  final List<RowAction> rowActions;
  final String? banner;
  final String newLabel;
  final bool showTitle;

  @override
  State<CrudPage> createState() => _CrudPageState();
}

class _CrudPageState extends State<CrudPage> {
  SupabaseClient get _db => Supabase.instance.client;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  late bool _showInactive = widget.showInactiveDefault;
  String? _quick;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _db
          .from(widget.table)
          .select(widget.select)
          .order(widget.orderBy, ascending: widget.ascending);
      _rows = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _cell(FieldDef f, Map<String, dynamic> row) {
    if (f.display != null) return f.display!(row);
    final v = row[f.key];
    if (v == null) return '-';
    switch (f.type) {
      case FieldType.money:
        return fmtMoney(v);
      case FieldType.number:
        return fmtNum(v);
      case FieldType.date:
        return fmtDate(v);
      case FieldType.dropdown:
        return f.options?['$v'] ?? '$v';
      default:
        return '$v';
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final cols = widget.fields.where((f) => f.inTable).toList();
    return _rows.where((r) {
      if (widget.activeKey != null &&
          !_showInactive &&
          r[widget.activeKey] == false) {
        return false;
      }
      if (_quick != null && !(widget.quickFilters[_quick]!(r))) return false;
      if (q.isEmpty) return true;
      return cols.any((f) => _cell(f, r).toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _toggleActive(Map<String, dynamic> row) async {
    final key = widget.activeKey!;
    final active = row[key] == true;
    final ok = await confirmDialog(
      context,
      title: active ? 'Inativar registro' : 'Reativar registro',
      message: active
          ? 'Deseja inativar este registro? O histórico será mantido.'
          : 'Deseja reativar este registro?',
    );
    if (!ok) return;
    try {
      await _db.from(widget.table).update({key: !active}).eq('id', row['id']);
      if (mounted) showSnack(context, active ? 'Registro inativado.' : 'Registro reativado.');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _runAction(RowAction a, Map<String, dynamic> row) async {
    try {
      await a.onTap(row);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final editing = row != null;

    final lookups = <String, List<Map<String, dynamic>>>{};
    try {
      for (final f in widget.fields
          .where((f) => f.type == FieldType.lookup && f.inForm)) {
        final data = await _db
            .from(f.lookupTable!)
            .select('id, ${f.lookupLabel}')
            .eq('ativo', true)
            .order(f.lookupLabel!);
        lookups[f.key] = List<Map<String, dynamic>>.from(data);
      }
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
      return;
    }
    if (!mounted) return;

    final formFields = widget.fields
        .where((f) => f.inForm && !(editing && f.createOnly))
        .toList();
    final ctrls = <String, TextEditingController>{};
    final values = <String, dynamic>{};

    for (final f in formFields) {
      final initial = editing ? row[f.key] : f.defaultValue;
      switch (f.type) {
        case FieldType.dropdown:
        case FieldType.lookup:
          values[f.key] = initial?.toString();
          break;
        case FieldType.date:
          values[f.key] = initial?.toString();
          ctrls[f.key] = TextEditingController(
              text: initial == null ? '' : fmtDate(initial));
          break;
        default:
          ctrls[f.key] =
              TextEditingController(text: initial == null ? '' : '$initial');
      }
    }

    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(editing ? 'Editar' : widget.newLabel),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final f in formFields)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _buildField(
                            ctx, f, ctrls, values, lookups, setLocal),
                      ),
                  ],
                ),
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
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final payload = <String, dynamic>{};
      for (final f in formFields) {
        switch (f.type) {
          case FieldType.dropdown:
          case FieldType.lookup:
          case FieldType.date:
            payload[f.key] = values[f.key];
            break;
          case FieldType.number:
          case FieldType.money:
            final t = ctrls[f.key]!.text.trim();
            payload[f.key] =
                t.isEmpty ? null : num.tryParse(t.replaceAll(',', '.'));
            break;
          default:
            final t = ctrls[f.key]!.text.trim();
            payload[f.key] = t.isEmpty ? null : t;
        }
      }
      try {
        if (editing) {
          await _db.from(widget.table).update(payload).eq('id', row['id']);
        } else {
          await _db.from(widget.table).insert(payload);
        }
        if (mounted) showSnack(context, 'Salvo com sucesso.');
        await _load();
      } catch (e) {
        if (mounted) showSnack(context, errorMessage(e), error: true);
      }
    }

    for (final c in ctrls.values) {
      c.dispose();
    }
  }

  Widget _buildField(
    BuildContext ctx,
    FieldDef f,
    Map<String, TextEditingController> ctrls,
    Map<String, dynamic> values,
    Map<String, List<Map<String, dynamic>>> lookups,
    void Function(void Function()) setLocal,
  ) {
    String? requiredValidator(String? v) =>
        f.required && (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;

    switch (f.type) {
      case FieldType.dropdown:
        return DropdownButtonFormField<String>(
          value: values[f.key],
          isExpanded: true,
          decoration: InputDecoration(labelText: f.label),
          items: [
            for (final e in f.options!.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setLocal(() => values[f.key] = v),
          validator: (v) => f.required && v == null ? 'Obrigatório' : null,
        );
      case FieldType.lookup:
        return DropdownButtonFormField<String>(
          value: values[f.key],
          isExpanded: true,
          decoration: InputDecoration(labelText: f.label),
          items: [
            for (final r in lookups[f.key] ?? const <Map<String, dynamic>>[])
              DropdownMenuItem(
                value: r['id'] as String,
                child: Text('${r[f.lookupLabel]}'),
              ),
          ],
          onChanged: (v) => setLocal(() => values[f.key] = v),
          validator: (v) => f.required && v == null ? 'Obrigatório' : null,
        );
      case FieldType.date:
        return TextFormField(
          controller: ctrls[f.key],
          readOnly: true,
          decoration: InputDecoration(
            labelText: f.label,
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
          ),
          validator: (_) =>
              f.required && values[f.key] == null ? 'Obrigatório' : null,
          onTap: () async {
            final initial =
                DateTime.tryParse('${values[f.key] ?? ''}') ?? DateTime.now();
            final d = await showDatePicker(
              context: ctx,
              initialDate: initial,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d != null) {
              values[f.key] = isoDate(d);
              ctrls[f.key]!.text = fmtDate(isoDate(d));
            }
          },
        );
      case FieldType.number:
      case FieldType.money:
        return TextFormField(
          controller: ctrls[f.key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: f.label,
            prefixText: f.type == FieldType.money ? 'R\$ ' : null,
          ),
          validator: (v) {
            final base = requiredValidator(v);
            if (base != null) return base;
            if (v != null &&
                v.trim().isNotEmpty &&
                num.tryParse(v.trim().replaceAll(',', '.')) == null) {
              return 'Número inválido';
            }
            return null;
          },
        );
      case FieldType.multiline:
        return TextFormField(
          controller: ctrls[f.key],
          maxLines: 3,
          decoration: InputDecoration(labelText: f.label),
          validator: requiredValidator,
        );
      case FieldType.email:
        return TextFormField(
          controller: ctrls[f.key],
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: f.label),
          validator: (v) {
            final base = requiredValidator(v);
            if (base != null) return base;
            if (v != null && v.trim().isNotEmpty && !v.contains('@')) {
              return 'E-mail inválido';
            }
            return null;
          },
        );
      case FieldType.phone:
        return TextFormField(
          controller: ctrls[f.key],
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: f.label),
          validator: requiredValidator,
        );
      case FieldType.text:
        return TextFormField(
          controller: ctrls[f.key],
          decoration: InputDecoration(labelText: f.label),
          validator: requiredValidator,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle)
          PageTitle(widget.title, actions: [
            if (widget.canCreate)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _openForm,
                icon: const Icon(Icons.add),
                label: Text(widget.newLabel),
              ),
          ])
        else if (widget.canCreate)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: Text(widget.newLabel),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Pesquisar...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (widget.activeKey != null) ...[
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Mostrar inativos'),
                selected: _showInactive,
                onSelected: (v) => setState(() => _showInactive = v),
              ),
            ],
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (widget.quickFilters.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final name in widget.quickFilters.keys)
                FilterChip(
                  label: Text(name),
                  selected: _quick == name,
                  onSelected: (v) => setState(() => _quick = v ? name : null),
                ),
            ],
          ),
        ],
        if (widget.banner != null) ...[
          const SizedBox(height: 8),
          Panel(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.banner!)),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: Panel(
            padding: EdgeInsets.zero,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(_error!, onRetry: _load)
                    : rows.isEmpty
                        ? const EmptyState('Nenhum registro encontrado.')
                        : _table(rows),
          ),
        ),
      ],
    );
  }

  Widget _table(List<Map<String, dynamic>> rows) {
    final cols = widget.fields.where((f) => f.inTable).toList();
    final hasActive = widget.activeKey != null;
    final hasActions = widget.canEdit || widget.rowActions.isNotEmpty;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            if (hasActive) const DataColumn(label: Text('Situação')),
            for (final f in cols) DataColumn(label: Text(f.label)),
            if (hasActions) const DataColumn(label: Text('Ações')),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                color: (widget.rowHighlight?.call(r) ?? false)
                    ? WidgetStateProperty.all(Colors.orange.withAlpha(40))
                    : null,
                cells: [
                  if (hasActive)
                    DataCell(Text(
                      r[widget.activeKey] == true ? 'Ativo' : 'Inativo',
                      style: TextStyle(
                        color: r[widget.activeKey] == true
                            ? Colors.greenAccent
                            : Colors.white54,
                      ),
                    )),
                  for (final f in cols) DataCell(Text(_cell(f, r))),
                  if (hasActions)
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.canEdit &&
                            (widget.rowEditable?.call(r) ?? true))
                          IconButton(
                            tooltip: 'Editar',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _openForm(r),
                          ),
                        if (widget.canEdit && hasActive)
                          IconButton(
                            tooltip: r[widget.activeKey] == true
                                ? 'Inativar'
                                : 'Reativar',
                            icon: Icon(r[widget.activeKey] == true
                                ? Icons.block
                                : Icons.restore),
                            onPressed: () => _toggleActive(r),
                          ),
                        for (final a in widget.rowActions)
                          if (a.visible?.call(r) ?? true)
                            IconButton(
                              tooltip: a.label,
                              icon: Icon(a.icon),
                              onPressed: () => _runAction(a, r),
                            ),
                      ],
                    )),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
