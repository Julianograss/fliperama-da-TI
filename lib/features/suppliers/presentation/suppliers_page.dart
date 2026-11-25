import 'package:flutter/material.dart';

import '../../../shared/widgets/crud_page.dart';

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CrudPage(
      title: 'Fornecedores',
      table: 'fornecedores',
      orderBy: 'razao_social',
      ascending: true,
      newLabel: 'Novo fornecedor',
      fields: [
        FieldDef('razao_social', 'Razão social', required: true),
        FieldDef('cnpj_cpf', 'CNPJ ou CPF', required: true),
        FieldDef('contato', 'Contato'),
        FieldDef('telefone', 'Telefone', type: FieldType.phone),
        FieldDef('email', 'E-mail', type: FieldType.email),
        FieldDef('categoria_fornecimento', 'Categoria de fornecimento'),
      ],
    );
  }
}
