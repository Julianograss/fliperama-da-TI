# ERP Fliperamada TI

ERP em **Flutter** + **Supabase** (Auth, PostgreSQL, RLS) hospedado na **Vercel**.
Tema gamer: fundo escuro, azul principal, roxo e ciano. Layout responsivo (menu lateral no desktop, gaveta no celular/tablet).

As telas de **Login** e **Cadastro** (`lib/features/auth`) não foram alteradas.

## Módulos

| Módulo | Quem acessa |
|---|---|
| Dashboard (cards, gráficos, últimas movimentações) | todos (financeiro só gerente/admin) |
| PDV / Vendas (+ cancelamento) | admin, gerente, operador de caixa |
| Produtos e Estoque | admin, gerente |
| Entradas de Mercadorias | admin, gerente |
| Saídas de Estoque | admin, gerente (manutenção também técnico) |
| Máquinas Arcade (+ histórico de manutenção) | admin, gerente, técnico |
| Fornecedores | admin, gerente |
| Funcionários | admin edita; gerente consulta |
| Escalas e Turnos + ponto | todos (turnos: gerente/admin editam) |
| Controle de Caixa | admin, gerente, operador de caixa |
| Contas a Pagar e Receber | admin, gerente |
| Relatórios (8 tipos) | admin, gerente (histórico de manutenção: + técnico) |
| Configurações | todos |

## Como as regras de negócio são garantidas

Tudo que é crítico roda **no banco** (`supabase/schema.sql`), não só na tela:

- Venda exige caixa aberto do próprio operador (RPC `registrar_venda`).
- Estoque nunca fica negativo (CHECK + validação nas RPCs); o saldo só muda por movimentação.
- Um caixa aberto por funcionário (índice único parcial).
- Desconto, sangria, estorno/cancelamento e ajuste manual: só gerente/admin.
- Fechamento com divergência exige justificativa (`fechar_caixa`).
- Sem exclusão física: triggers bloqueiam DELETE; movimentações são imutáveis; usa-se inativação/cancelamento.
- Saída para manutenção exige máquina (CHECK + RPC).
- Data, hora e responsável em todas as operações importantes.
- Funcionário inativo não acessa nada: as funções de permissão ignoram inativos.
- Senhas ficam só no Supabase Auth.

**Primeiro acesso:** o primeiro usuário cadastrado vira **administrador ativo**. Os demais ficam **inativos** (tela "Acesso pendente") até um administrador ativá-los em *Funcionários* e definir o nível de acesso.

## Como rodar

1. Gere as plataformas que faltam (o zip traz só `web/`):
   ```bash
   flutter create . --platforms=web,android,ios --project-name erp_base
   flutter pub get
   ```
2. No Supabase: crie o projeto, abra o **SQL Editor**, rode `supabase/schema.sql` inteiro.
3. Copie `env.example.json` para `env.json` e preencha URL e anon key.
4. Rode:
   ```bash
   flutter run -d chrome --dart-define-from-file=env.json
   ```
5. Cadastre-se pela tela de cadastro (será o administrador) e use o sistema.

## Deploy (GitHub + Vercel)

Suba para o GitHub, importe na Vercel e defina `SUPABASE_URL` e `SUPABASE_ANON_KEY`.
No Supabase, em *Authentication → URL Configuration*, coloque a URL da Vercel.
Para testar rápido, desative "Confirm email" em *Authentication → Providers → Email*.

## Pontos de atenção / próximos passos

- O código não foi compilado no ambiente em que foi gerado: se o primeiro `flutter run` acusar erro, corrija conforme a mensagem.
- Autorização de gerente é por **perfil de quem está logado** (o gerente faz a operação ou assume o terminal). Autorização por senha de gerente sobre outro operador pode ser um próximo passo.
- Gerentes enxergam o salário na tela de Funcionários (política RLS de leitura); restrinja se necessário.
- Imagem do produto: hoje é um campo de URL; upload via Supabase Storage fica para uma próxima etapa.
- Faturamento/estoque/contas atrasadas: "Atrasado" é calculado pela data de vencimento.
- Fuso usado nos relatórios: America/Sao_Paulo.
