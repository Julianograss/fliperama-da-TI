import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../shared/widgets/crud_page.dart';

const categoriasProduto = {
  'Fichas e Créditos': 'Fichas e Créditos',
  'Bebidas': 'Bebidas',
  'Snacks': 'Snacks',
  'Peças de Manutenção': 'Peças de Manutenção',
};

bool _estoqueBaixo(Map<String, dynamic> r) =>
    toD(r['quantidade_estoque']) <= toD(r['estoque_minimo']);

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CrudPage(
      title: 'Produtos e Estoque',
      table: 'produtos',
      select: '*, fornecedores(razao_social)',
      orderBy: 'nome',
      ascending: true,
      newLabel: 'Novo produto',
      rowHighlight: _estoqueBaixo,
      banner:
          'Linhas em laranja = estoque igual ou abaixo do mínimo. O saldo só muda por '
          'movimentações (entradas, saídas e vendas).',
      quickFilters: {
        'Estoque baixo': _estoqueBaixo,
        for (final c in categoriasProduto.keys) c: (r) => r['categoria'] == c,
      },
      fields: [
        const FieldDef('nome', 'Produto', required: true),
        const FieldDef('codigo_interno', 'Código interno', required: true),
        const FieldDef('categoria', 'Categoria',
            type: FieldType.dropdown, required: true, options: categoriasProduto),
        const FieldDef('unidade_medida', 'Unidade',
            type: FieldType.dropdown,
            required: true,
            defaultValue: 'un',
            options: {
              'un': 'Unidade (un)',
              'cx': 'Caixa (cx)',
              'pct': 'Pacote (pct)',
              'kg': 'Quilo (kg)',
              'l': 'Litro (l)',
            }),
        const FieldDef('preco_custo', 'Preço de custo',
            type: FieldType.money, required: true, defaultValue: 0),
        const FieldDef('preco_venda', 'Preço de venda',
            type: FieldType.money, required: true, defaultValue: 0),
        const FieldDef('quantidade_estoque', 'Quantidade em estoque',
            type: FieldType.number, createOnly: true, defaultValue: 0),
        const FieldDef('estoque_minimo', 'Estoque mínimo',
            type: FieldType.number, defaultValue: 0),
        FieldDef('fornecedor_id', 'Fornecedor',
            type: FieldType.lookup,
            lookupTable: 'fornecedores',
            lookupLabel: 'razao_social',
            display: (r) =>
                (r['fornecedores'] as Map?)?['razao_social']?.toString() ?? '-'),
        const FieldDef('descricao', 'Descrição',
            type: FieldType.multiline, inTable: false),
        const FieldDef('imagem_url', 'URL da imagem (opcional)', inTable: false),
      ],
    );
  }
}
