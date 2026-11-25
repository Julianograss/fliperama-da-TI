import 'package:flutter/material.dart';

import '../../../core/services/user_session.dart';
import '../../../shared/widgets/crud_page.dart';

const perfisOpcoes = {
  'administrador': 'Administrador',
  'gerente': 'Gerente',
  'operador_caixa': 'Operador de Caixa',
  'tecnico': 'Técnico',
};

class EmployeesPage extends StatelessWidget {
  const EmployeesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = UserSession.instance.user?.isAdmin ?? false;
    return CrudPage(
      title: 'Funcionários',
      table: 'colaboradores',
      orderBy: 'nome_completo',
      ascending: true,
      canCreate: false,
      canEdit: isAdmin,
      showInactiveDefault: true,
      rowHighlight: (r) => r['ativo'] == false,
      banner: isAdmin
          ? 'Novos funcionários se cadastram na tela de cadastro e ficam inativos. '
              'Edite os dados, defina o nível de acesso e reative (ícone de restaurar) para liberar o acesso.'
          : 'Somente administradores podem editar funcionários.',
      fields: const [
        FieldDef('nome_completo', 'Nome completo', required: true),
        FieldDef('cpf', 'CPF'),
        FieldDef('cargo', 'Cargo'),
        FieldDef('telefone', 'Telefone', type: FieldType.phone),
        FieldDef('email', 'E-mail', type: FieldType.email),
        FieldDef('data_admissao', 'Data de admissão', type: FieldType.date),
        FieldDef('salario_base', 'Salário base', type: FieldType.money),
        FieldDef('perfil_id', 'Nível de acesso',
            type: FieldType.dropdown, required: true, options: perfisOpcoes),
      ],
    );
  }
}
