import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/user_session.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/crud_page.dart';

const turnosOpcoes = {
  'manha': 'Manhã',
  'tarde': 'Tarde',
  'noite': 'Noite',
  'fim_de_semana': 'Fim de semana',
};

class ShiftsPage extends StatelessWidget {
  const ShiftsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final gestor = UserSession.instance.user?.isGestor ?? false;
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle('Escalas e Turnos'),
          const TabBar(tabs: [
            Tab(text: 'Meu ponto'),
            Tab(text: 'Turnos'),
            Tab(text: 'Registros de ponto'),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(children: [
              const _PontoTab(),
              CrudPage(
                title: 'Turnos',
                showTitle: false,
                table: 'escalas_turnos',
                select: '*, colaboradores(nome_completo)',
                canCreate: gestor,
                canEdit: gestor,
                newLabel: 'Associar funcionário',
                fields: [
                  FieldDef('colaborador_id', 'Funcionário',
                      type: FieldType.lookup,
                      required: true,
                      lookupTable: 'colaboradores',
                      lookupLabel: 'nome_completo',
                      display: (r) =>
                          (r['colaboradores'] as Map?)?['nome_completo']?.toString() ??
                          '-'),
                  const FieldDef('turno', 'Turno',
                      type: FieldType.dropdown,
                      required: true,
                      options: turnosOpcoes),
                ],
              ),
              const _PontoRegistros(),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PontoTab extends StatefulWidget {
  const _PontoTab();

  @override
  State<_PontoTab> createState() => _PontoTabState();
}

class _PontoTabState extends State<_PontoTab> {
  SupabaseClient get _db => Supabase.instance.client;
  Map<String, dynamic>? _aberto;
  bool _loading = true;
  bool _busy = false;
  String? _error;

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
      _aberto = await _db
          .from('registros_ponto')
          .select()
          .eq('colaborador_id', UserSession.instance.user!.id)
          .isFilter('fim', null)
          .maybeSingle();
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle() async {
    final iniciando = _aberto == null;
    final ok = await confirmDialog(
      context,
      title: iniciando ? 'Iniciar expediente' : 'Encerrar expediente',
      message: iniciando
          ? 'Registrar o início do seu expediente agora?'
          : 'Registrar o fim do seu expediente agora?',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _db.rpc(iniciando ? 'iniciar_expediente' : 'encerrar_expediente');
      if (mounted) {
        showSnack(context,
            iniciando ? 'Expediente iniciado.' : 'Expediente encerrado.');
      }
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(_error!, onRetry: _load);
    final iniciado = _aberto != null;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(iniciado ? Icons.timer : Icons.timer_off_outlined, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    iniciado
                        ? 'Expediente em andamento desde ${fmtDateTime(_aberto!['inicio'])}'
                        : 'Nenhum expediente em andamento.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _toggle,
                icon: Icon(iniciado ? Icons.stop : Icons.play_arrow),
                label: Text(iniciado ? 'Encerrar expediente' : 'Iniciar expediente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PontoRegistros extends StatelessWidget {
  const _PontoRegistros();

  String _duracao(dynamic inicio, dynamic fim) {
    final i = DateTime.tryParse('$inicio');
    final f = DateTime.tryParse('$fim');
    if (i == null || f == null) return 'Em andamento';
    final d = f.difference(i);
    return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}min';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Supabase.instance.client
          .from('registros_ponto')
          .select('*, colaboradores(nome_completo)')
          .order('inicio', ascending: false)
          .limit(100),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return ErrorState(errorMessage(snap.error!));
        final rows = List<Map<String, dynamic>>.from(snap.data as List);
        if (rows.isEmpty) return const EmptyState('Nenhum registro de ponto.');
        return Panel(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Funcionário')),
                  DataColumn(label: Text('Início')),
                  DataColumn(label: Text('Fim')),
                  DataColumn(label: Text('Duração')),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [
                      DataCell(Text(
                          '${(r['colaboradores'] as Map?)?['nome_completo'] ?? '-'}')),
                      DataCell(Text(fmtDateTime(r['inicio']))),
                      DataCell(Text(r['fim'] == null ? '-' : fmtDateTime(r['fim']))),
                      DataCell(Text(_duracao(r['inicio'], r['fim']))),
                    ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
