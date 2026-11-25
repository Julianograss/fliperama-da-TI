-- =====================================================================
-- ERP Fliperamada TI - schema completo (Supabase / PostgreSQL)
-- Rode inteiro no SQL Editor de um projeto novo.
-- Se você já rodou o schema da versão anterior (profiles/sectors/products),
-- descomente as linhas abaixo antes:
-- drop table if exists public.stock_movements, public.products, public.sectors, public.profiles cascade;
-- =====================================================================

-- ========== PERFIS DE ACESSO ==========
create table if not exists public.perfis_acesso (
  codigo text primary key,
  nome text not null,
  descricao text,
  pode_desconto boolean not null default false,
  pode_estorno boolean not null default false,
  pode_relatorios boolean not null default false
);

insert into public.perfis_acesso (codigo, nome, descricao, pode_desconto, pode_estorno, pode_relatorios) values
  ('administrador',  'Administrador',     'Acesso completo ao sistema', true,  true,  true),
  ('gerente',        'Gerente',           'Operações, estornos e relatórios', true, true, true),
  ('operador_caixa', 'Operador de Caixa', 'PDV e funcionalidades de caixa', false, false, false),
  ('tecnico',        'Técnico',           'Máquinas e saídas de peças para manutenção', false, false, false)
on conflict (codigo) do nothing;

-- ========== COLABORADORES (ligados ao Supabase Auth; sem senha aqui) ==========
create table if not exists public.colaboradores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id),
  nome_completo text not null,
  cpf text unique,
  cargo text,
  telefone text,
  email text,
  data_admissao date,
  salario_base numeric(12,2) check (salario_base is null or salario_base >= 0),
  perfil_id text not null default 'operador_caixa' references public.perfis_acesso(codigo),
  ativo boolean not null default false,
  criado_em timestamptz not null default now()
);

-- ========== FUNÇÕES AUXILIARES DE PERMISSÃO ==========
create or replace function public.meu_colaborador_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.colaboradores where user_id = auth.uid() and ativo limit 1;
$$;

create or replace function public.meu_perfil()
returns text language sql stable security definer set search_path = public as $$
  select perfil_id from public.colaboradores where user_id = auth.uid() and ativo limit 1;
$$;

create or replace function public.tem_perfil(variadic p_perfis text[])
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.meu_perfil() = any(p_perfis), false);
$$;

create or replace function public.exigir_perfil(variadic p_perfis text[])
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if public.meu_colaborador_id() is null then
    raise exception 'Acesso negado: colaborador inativo ou não cadastrado.';
  end if;
  if not public.tem_perfil(variadic p_perfis) then
    raise exception 'Você não tem permissão para esta operação.';
  end if;
end;
$$;

-- Cria o colaborador ao cadastrar um usuário.
-- O PRIMEIRO usuário vira administrador ativo; os demais ficam inativos
-- até um administrador liberar (regra: inativos não acessam o sistema).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_primeiro boolean;
begin
  select not exists (select 1 from public.colaboradores) into v_primeiro;
  insert into public.colaboradores (user_id, nome_completo, email, perfil_id, ativo, data_admissao)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(new.email, '@', 1)),
    new.email,
    case when v_primeiro then 'administrador' else 'operador_caixa' end,
    v_primeiro,
    case when v_primeiro then current_date end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Impede o usuário de mudar o próprio perfil/situação (evita bloqueio acidental)
create or replace function public.proteger_colaborador()
returns trigger language plpgsql as $$
begin
  if old.user_id is not null and old.user_id = auth.uid()
     and (new.ativo is distinct from old.ativo or new.perfil_id is distinct from old.perfil_id) then
    raise exception 'Você não pode alterar o seu próprio perfil ou situação.';
  end if;
  if new.user_id is distinct from old.user_id then
    raise exception 'O vínculo com o usuário de login não pode ser alterado.';
  end if;
  return new;
end;
$$;
drop trigger if exists proteger_colaborador on public.colaboradores;
create trigger proteger_colaborador before update on public.colaboradores
  for each row execute function public.proteger_colaborador();

-- ========== FORNECEDORES ==========
create table if not exists public.fornecedores (
  id uuid primary key default gen_random_uuid(),
  razao_social text not null,
  cnpj_cpf text not null unique,
  contato text,
  telefone text,
  email text,
  categoria_fornecimento text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

-- ========== PRODUTOS ==========
create table if not exists public.produtos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  codigo_interno text not null unique,
  categoria text not null check (categoria in ('Fichas e Créditos','Bebidas','Snacks','Peças de Manutenção')),
  unidade_medida text not null default 'un',
  preco_custo numeric(12,2) not null default 0 check (preco_custo >= 0),
  preco_venda numeric(12,2) not null default 0 check (preco_venda >= 0),
  quantidade_estoque numeric(12,3) not null default 0 constraint produtos_estoque_nao_negativo check (quantidade_estoque >= 0),
  estoque_minimo numeric(12,3) not null default 0 check (estoque_minimo >= 0),
  fornecedor_id uuid references public.fornecedores(id),
  descricao text,
  imagem_url text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

-- ========== MÁQUINAS ARCADE ==========
create table if not exists public.maquinas_arcade (
  id uuid primary key default gen_random_uuid(),
  nome_jogo text not null,
  numero_patrimonio text not null unique,
  data_aquisicao date,
  status text not null default 'ativa' check (status in ('ativa','em_manutencao','inativa')),
  criado_em timestamptz not null default now()
);

-- ========== ESCALAS E PONTO ==========
create table if not exists public.escalas_turnos (
  id uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.colaboradores(id),
  turno text not null check (turno in ('manha','tarde','noite','fim_de_semana')),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (colaborador_id, turno)
);

create table if not exists public.registros_ponto (
  id uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.colaboradores(id),
  inicio timestamptz not null default now(),
  fim timestamptz,
  criado_em timestamptz not null default now(),
  check (fim is null or fim >= inicio)
);
create unique index if not exists registros_ponto_um_aberto
  on public.registros_ponto (colaborador_id) where fim is null;

-- ========== CAIXAS ==========
create table if not exists public.caixas (
  id uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.colaboradores(id),
  valor_inicial numeric(12,2) not null check (valor_inicial >= 0),
  aberto_em timestamptz not null default now(),
  fechado_em timestamptz,
  fechado_por uuid references public.colaboradores(id),
  status text not null default 'aberto' check (status in ('aberto','fechado')),
  valores_esperados jsonb,
  valores_contados jsonb,
  diferenca numeric(12,2),
  justificativa_divergencia text,
  criado_em timestamptz not null default now()
);
-- Regra 3: um funcionário não pode ter dois caixas abertos
create unique index if not exists caixas_um_aberto_por_colaborador
  on public.caixas (colaborador_id) where status = 'aberto';

-- ========== VENDAS ==========
create table if not exists public.vendas (
  id uuid primary key default gen_random_uuid(),
  numero bigint generated always as identity,
  caixa_id uuid not null references public.caixas(id),
  colaborador_id uuid not null references public.colaboradores(id),
  subtotal numeric(12,2) not null default 0,
  desconto numeric(12,2) not null default 0 check (desconto >= 0),
  total numeric(12,2) not null default 0,
  valor_recebido numeric(12,2) not null default 0,
  troco numeric(12,2) not null default 0,
  pagamentos jsonb not null default '[]'::jsonb,
  status text not null default 'concluida' check (status in ('concluida','cancelada')),
  cancelada_em timestamptz,
  cancelada_por uuid references public.colaboradores(id),
  motivo_cancelamento text,
  criado_em timestamptz not null default now()
);

create table if not exists public.itens_venda (
  id uuid primary key default gen_random_uuid(),
  venda_id uuid not null references public.vendas(id),
  produto_id uuid not null references public.produtos(id),
  quantidade numeric(12,3) not null check (quantidade > 0),
  preco_unitario numeric(12,2) not null,
  subtotal numeric(12,2) not null
);

-- ========== MOVIMENTAÇÕES DE CAIXA ==========
create table if not exists public.movimentacoes_caixa (
  id uuid primary key default gen_random_uuid(),
  caixa_id uuid not null references public.caixas(id),
  tipo text not null check (tipo in ('venda','suprimento','sangria','estorno')),
  forma_pagamento text not null check (forma_pagamento in ('dinheiro','pix','debito','credito')),
  valor numeric(12,2) not null check (valor > 0),
  venda_id uuid references public.vendas(id),
  justificativa text,
  colaborador_id uuid not null references public.colaboradores(id),
  criado_em timestamptz not null default now()
);

-- ========== MOVIMENTAÇÕES DE ESTOQUE ==========
create table if not exists public.movimentacoes_estoque (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid,
  produto_id uuid not null references public.produtos(id),
  tipo text not null check (tipo in ('entrada','saida')),
  motivo text not null check (motivo in ('compra','venda','manutencao','perda','vencido','danificado','ajuste','estorno')),
  quantidade numeric(12,3) not null check (quantidade > 0),
  custo_unitario numeric(12,2),
  fornecedor_id uuid references public.fornecedores(id),
  maquina_id uuid references public.maquinas_arcade(id),
  venda_id uuid references public.vendas(id),
  colaborador_id uuid not null references public.colaboradores(id),
  observacao text,
  data_movimento date not null default current_date,
  criado_em timestamptz not null default now(),
  -- Regra 7: peça retirada para manutenção deve ter máquina
  constraint mov_estoque_manutencao_exige_maquina check (motivo <> 'manutencao' or maquina_id is not null)
);

-- ========== CONTAS FINANCEIRAS ==========
create table if not exists public.contas_financeiras (
  id uuid primary key default gen_random_uuid(),
  descricao text not null,
  categoria text not null,
  tipo text not null check (tipo in ('pagar','receber')),
  valor numeric(12,2) not null check (valor > 0),
  data_vencimento date not null,
  data_pagamento date,
  fornecedor_id uuid references public.fornecedores(id),
  status text not null default 'pendente' check (status in ('pendente','pago','atrasado','cancelado')),
  criado_em timestamptz not null default now()
);

-- ========== TRIGGERS DE ESTOQUE ==========
-- Aplica a movimentação ao saldo (regra 2: saldo nunca fica negativo - CHECK em produtos)
create or replace function public.aplicar_movimentacao_estoque()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('app.stock_update', '1', true);
  if new.tipo = 'entrada' then
    update public.produtos set quantidade_estoque = quantidade_estoque + new.quantidade where id = new.produto_id;
  else
    update public.produtos set quantidade_estoque = quantidade_estoque - new.quantidade where id = new.produto_id;
  end if;
  perform set_config('app.stock_update', '0', true);
  return new;
end;
$$;
drop trigger if exists on_movimentacao_estoque on public.movimentacoes_estoque;
create trigger on_movimentacao_estoque after insert on public.movimentacoes_estoque
  for each row execute function public.aplicar_movimentacao_estoque();

-- Saldo só muda por movimentação (regra 4: ajuste manual passa pela RPC com permissão)
create or replace function public.proteger_estoque_produto()
returns trigger language plpgsql as $$
begin
  if new.quantidade_estoque is distinct from old.quantidade_estoque
     and coalesce(current_setting('app.stock_update', true), '0') <> '1' then
    raise exception 'O estoque só pode ser alterado por movimentações.';
  end if;
  return new;
end;
$$;
drop trigger if exists proteger_estoque_produto on public.produtos;
create trigger proteger_estoque_produto before update on public.produtos
  for each row execute function public.proteger_estoque_produto();

-- Estoque inicial informado no cadastro vira uma movimentação (mantém o histórico)
create or replace function public.estoque_inicial_produto()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_qtd numeric := new.quantidade_estoque;
begin
  if v_qtd > 0 then
    perform set_config('app.stock_update', '1', true);
    update public.produtos set quantidade_estoque = 0 where id = new.id;
    perform set_config('app.stock_update', '0', true);
    insert into public.movimentacoes_estoque (produto_id, tipo, motivo, quantidade, colaborador_id, observacao)
    values (new.id, 'entrada', 'ajuste', v_qtd, public.meu_colaborador_id(), 'Estoque inicial do cadastro');
  end if;
  return new;
end;
$$;
drop trigger if exists estoque_inicial_produto on public.produtos;
create trigger estoque_inicial_produto after insert on public.produtos
  for each row execute function public.estoque_inicial_produto();

-- ========== REGRA 6: NADA É EXCLUÍDO FISICAMENTE; HISTÓRICO É IMUTÁVEL ==========
create or replace function public.bloquear_exclusao()
returns trigger language plpgsql as $$
begin
  raise exception 'Exclusão não permitida em %: use inativação ou cancelamento.', tg_table_name;
end;
$$;

create or replace function public.bloquear_alteracao()
returns trigger language plpgsql as $$
begin
  raise exception 'Registros de % não podem ser alterados.', tg_table_name;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['colaboradores','fornecedores','produtos','maquinas_arcade','escalas_turnos',
    'registros_ponto','caixas','movimentacoes_caixa','vendas','itens_venda','movimentacoes_estoque','contas_financeiras']
  loop
    execute format('drop trigger if exists bloquear_exclusao on public.%I', t);
    execute format('create trigger bloquear_exclusao before delete on public.%I for each row execute function public.bloquear_exclusao()', t);
  end loop;
  foreach t in array array['movimentacoes_estoque','movimentacoes_caixa','itens_venda']
  loop
    execute format('drop trigger if exists bloquear_alteracao on public.%I', t);
    execute format('create trigger bloquear_alteracao before update on public.%I for each row execute function public.bloquear_alteracao()', t);
  end loop;
end;
$$;

-- ========== VIEW DE FLUXO FINANCEIRO ==========
create or replace view public.vw_fluxo_financeiro with (security_invoker = true) as
  select (criado_em at time zone 'America/Sao_Paulo')::date as dia, valor as entrada, 0::numeric as saida
    from public.movimentacoes_caixa where tipo = 'venda'
  union all
  select (criado_em at time zone 'America/Sao_Paulo')::date, 0::numeric, valor
    from public.movimentacoes_caixa where tipo = 'estorno'
  union all
  select data_pagamento, valor, 0::numeric
    from public.contas_financeiras where status = 'pago' and tipo = 'receber' and data_pagamento is not null
  union all
  select data_pagamento, 0::numeric, valor
    from public.contas_financeiras where status = 'pago' and tipo = 'pagar' and data_pagamento is not null;

-- =====================================================================
-- OPERAÇÕES (RPC) - toda regra crítica é validada aqui, no banco
-- =====================================================================

-- ---------- ENTRADA DE MERCADORIAS ----------
create or replace function public.registrar_entrada(p_fornecedor_id uuid, p_data date, p_observacao text, p_itens jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_doc uuid := gen_random_uuid();
  v_colab uuid;
  v_item jsonb;
  v_prod uuid;
  v_qtd numeric;
  v_custo numeric;
begin
  perform public.exigir_perfil('administrador','gerente');
  v_colab := public.meu_colaborador_id();
  if p_itens is null or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe ao menos um produto.';
  end if;
  for v_item in select * from jsonb_array_elements(p_itens) loop
    v_prod := (v_item ->> 'produto_id')::uuid;
    v_qtd := (v_item ->> 'quantidade')::numeric;
    v_custo := (v_item ->> 'custo_unitario')::numeric;
    if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade inválida.'; end if;
    if v_custo is null or v_custo < 0 then raise exception 'Custo unitário inválido.'; end if;
    if not exists (select 1 from public.produtos where id = v_prod and ativo) then
      raise exception 'Produto inativo ou inexistente.';
    end if;
    insert into public.movimentacoes_estoque
      (documento_id, produto_id, tipo, motivo, quantidade, custo_unitario, fornecedor_id, colaborador_id, observacao, data_movimento)
    values (v_doc, v_prod, 'entrada', 'compra', v_qtd, v_custo, p_fornecedor_id, v_colab, p_observacao, coalesce(p_data, current_date));
    update public.produtos set preco_custo = v_custo where id = v_prod;
  end loop;
  return v_doc;
end;
$$;

-- ---------- SAÍDA DE ESTOQUE ----------
create or replace function public.registrar_saida(p_produto_id uuid, p_quantidade numeric, p_motivo text, p_maquina_id uuid, p_observacao text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_colab uuid;
  v_estoque numeric;
  v_nome text;
  v_id uuid;
begin
  if p_motivo not in ('manutencao','perda','vencido','danificado','ajuste') then
    raise exception 'Motivo inválido.';
  end if;
  if p_motivo = 'manutencao' then
    perform public.exigir_perfil('administrador','gerente','tecnico');
  else
    -- perdas, vencidos, danificados e ajustes manuais: gerente ou administrador (regra 4)
    perform public.exigir_perfil('administrador','gerente');
  end if;
  v_colab := public.meu_colaborador_id();
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade inválida.'; end if;
  if p_motivo = 'manutencao' and p_maquina_id is null then
    raise exception 'Selecione a máquina para saídas de manutenção.';
  end if;
  select quantidade_estoque, nome into v_estoque, v_nome
    from public.produtos where id = p_produto_id and ativo for update;
  if not found then raise exception 'Produto inativo ou inexistente.'; end if;
  if v_estoque < p_quantidade then
    raise exception 'Estoque insuficiente para "%": disponível %.', v_nome, v_estoque;
  end if;
  insert into public.movimentacoes_estoque (produto_id, tipo, motivo, quantidade, maquina_id, colaborador_id, observacao)
  values (p_produto_id, 'saida', p_motivo, p_quantidade, p_maquina_id, v_colab, p_observacao)
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------- CAIXA ----------
create or replace function public.abrir_caixa(p_valor_inicial numeric)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_colab uuid; v_id uuid;
begin
  perform public.exigir_perfil('administrador','gerente','operador_caixa');
  if p_valor_inicial is null or p_valor_inicial < 0 then raise exception 'Valor inicial inválido.'; end if;
  v_colab := public.meu_colaborador_id();
  if exists (select 1 from public.caixas where colaborador_id = v_colab and status = 'aberto') then
    raise exception 'Você já possui um caixa aberto.';
  end if;
  insert into public.caixas (colaborador_id, valor_inicial) values (v_colab, p_valor_inicial) returning id into v_id;
  return v_id;
end;
$$;

-- Saldo esperado por forma de pagamento (dinheiro inclui o valor inicial)
create or replace function public.calcular_esperado_caixa(p_caixa_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.caixas c
    where c.id = p_caixa_id
      and (c.colaborador_id = public.meu_colaborador_id() or public.tem_perfil('administrador','gerente'))
  ) then
    raise exception 'Acesso negado ao caixa.';
  end if;
  return (
    select coalesce(jsonb_object_agg(forma, total), '{}'::jsonb) from (
      select forma, sum(v) as total from (
        select m.forma_pagamento as forma,
               case when m.tipo in ('venda','suprimento') then m.valor else -m.valor end as v
          from public.movimentacoes_caixa m where m.caixa_id = p_caixa_id
        union all
        select 'dinheiro'::text, c.valor_inicial from public.caixas c where c.id = p_caixa_id
      ) x group by forma
    ) s
  );
end;
$$;

-- Sangria (somente gerente/admin) e suprimento
create or replace function public.movimentar_caixa(p_tipo text, p_valor numeric, p_justificativa text, p_caixa_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_colab uuid; v_caixa uuid; v_cx public.caixas%rowtype; v_saldo numeric; v_id uuid;
begin
  if p_tipo not in ('sangria','suprimento') then raise exception 'Tipo de movimentação inválido.'; end if;
  if p_tipo = 'sangria' then
    perform public.exigir_perfil('administrador','gerente');  -- regra 4
  else
    perform public.exigir_perfil('administrador','gerente','operador_caixa');
  end if;
  if p_valor is null or p_valor <= 0 then raise exception 'Valor inválido.'; end if;
  if coalesce(trim(p_justificativa), '') = '' then raise exception 'Informe a justificativa.'; end if;
  v_colab := public.meu_colaborador_id();
  v_caixa := coalesce(p_caixa_id, (select id from public.caixas where colaborador_id = v_colab and status = 'aberto'));
  select * into v_cx from public.caixas where id = v_caixa and status = 'aberto' for update;
  if not found then raise exception 'Nenhum caixa aberto encontrado.'; end if;
  if v_cx.colaborador_id <> v_colab and not public.tem_perfil('administrador','gerente') then
    raise exception 'Você não pode movimentar o caixa de outro operador.';
  end if;
  if p_tipo = 'sangria' then
    v_saldo := coalesce((public.calcular_esperado_caixa(v_cx.id) ->> 'dinheiro')::numeric, 0);
    if p_valor > v_saldo then
      raise exception 'Sangria maior que o saldo em dinheiro do caixa (%).', v_saldo;
    end if;
  end if;
  insert into public.movimentacoes_caixa (caixa_id, tipo, forma_pagamento, valor, justificativa, colaborador_id)
  values (v_cx.id, p_tipo, 'dinheiro', p_valor, p_justificativa, v_colab)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.fechar_caixa(p_caixa_id uuid, p_contados jsonb, p_justificativa text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cx public.caixas%rowtype; v_esp jsonb; v_forma text; v_dif numeric; v_dif_total numeric := 0; v_div boolean := false;
begin
  perform public.exigir_perfil('administrador','gerente','operador_caixa');
  select * into v_cx from public.caixas where id = p_caixa_id for update;
  if not found then raise exception 'Caixa não encontrado.'; end if;
  if v_cx.status <> 'aberto' then raise exception 'Este caixa já está fechado.'; end if;
  if v_cx.colaborador_id <> public.meu_colaborador_id() and not public.tem_perfil('administrador','gerente') then
    raise exception 'Apenas o operador do caixa ou um gerente pode fechá-lo.';
  end if;
  v_esp := public.calcular_esperado_caixa(p_caixa_id);
  foreach v_forma in array array['dinheiro','pix','debito','credito'] loop
    v_dif := coalesce((p_contados ->> v_forma)::numeric, 0) - coalesce((v_esp ->> v_forma)::numeric, 0);
    if round(v_dif, 2) <> 0 then v_div := true; end if;
    v_dif_total := v_dif_total + v_dif;
  end loop;
  -- regra 5: divergência exige justificativa
  if v_div and coalesce(trim(p_justificativa), '') = '' then
    raise exception 'Há divergência no fechamento. Informe a justificativa.';
  end if;
  update public.caixas set
    status = 'fechado', fechado_em = now(), fechado_por = public.meu_colaborador_id(),
    valores_esperados = v_esp, valores_contados = p_contados,
    diferenca = round(v_dif_total, 2), justificativa_divergencia = nullif(trim(p_justificativa), '')
  where id = p_caixa_id;
  return jsonb_build_object('diferenca', round(v_dif_total, 2), 'divergente', v_div);
end;
$$;

-- ---------- VENDA (PDV) ----------
create or replace function public.registrar_venda(p_itens jsonb, p_desconto numeric, p_pagamentos jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_colab uuid; v_caixa uuid; v_venda uuid := gen_random_uuid();
  v_item jsonb; v_prod record; v_qtd numeric; v_linha numeric;
  v_subtotal numeric := 0; v_desc numeric := coalesce(p_desconto, 0); v_total numeric;
  v_pago numeric := 0; v_dinheiro numeric := 0; v_troco numeric := 0; v_pg record; v_liq numeric;
begin
  perform public.exigir_perfil('administrador','gerente','operador_caixa');
  v_colab := public.meu_colaborador_id();
  -- regra 1: sem caixa aberto vinculado ao operador não há venda
  select id into v_caixa from public.caixas where colaborador_id = v_colab and status = 'aberto';
  if v_caixa is null then
    raise exception 'Não é possível vender sem um caixa aberto para o seu usuário.';
  end if;
  if p_itens is null or jsonb_array_length(p_itens) = 0 then raise exception 'O carrinho está vazio.'; end if;
  if v_desc < 0 then raise exception 'Desconto inválido.'; end if;
  if v_desc > 0 and not public.tem_perfil('administrador','gerente') then
    raise exception 'Desconto requer autorização de gerente ou administrador.';
  end if;

  insert into public.vendas (id, caixa_id, colaborador_id) values (v_venda, v_caixa, v_colab);

  for v_item in select * from jsonb_array_elements(p_itens) loop
    v_qtd := (v_item ->> 'quantidade')::numeric;
    if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade inválida.'; end if;
    select id, nome, preco_venda, quantidade_estoque, ativo into v_prod
      from public.produtos where id = (v_item ->> 'produto_id')::uuid for update;
    if not found then raise exception 'Produto não encontrado.'; end if;
    if not v_prod.ativo then raise exception 'Produto "%" está inativo.', v_prod.nome; end if;
    -- regra 2: sem estoque negativo
    if v_prod.quantidade_estoque < v_qtd then
      raise exception 'Estoque insuficiente para "%": disponível %.', v_prod.nome, v_prod.quantidade_estoque;
    end if;
    v_linha := round(v_qtd * v_prod.preco_venda, 2);   -- preço sempre vem do banco
    insert into public.itens_venda (venda_id, produto_id, quantidade, preco_unitario, subtotal)
      values (v_venda, v_prod.id, v_qtd, v_prod.preco_venda, v_linha);
    insert into public.movimentacoes_estoque (produto_id, tipo, motivo, quantidade, venda_id, colaborador_id)
      values (v_prod.id, 'saida', 'venda', v_qtd, v_venda, v_colab);
    v_subtotal := v_subtotal + v_linha;
  end loop;

  if v_desc > v_subtotal then raise exception 'O desconto não pode ser maior que o subtotal.'; end if;
  v_total := v_subtotal - v_desc;

  for v_pg in
    select forma, sum(valor) as valor
      from jsonb_to_recordset(coalesce(p_pagamentos, '[]'::jsonb)) as x(forma text, valor numeric)
     group by forma
  loop
    if v_pg.forma not in ('dinheiro','pix','debito','credito') then raise exception 'Forma de pagamento inválida.'; end if;
    if v_pg.valor is null or v_pg.valor <= 0 then raise exception 'Valor de pagamento inválido.'; end if;
    v_pago := v_pago + v_pg.valor;
    if v_pg.forma = 'dinheiro' then v_dinheiro := v_pg.valor; end if;
  end loop;

  if v_pago < v_total then
    raise exception 'Valor pago (%) é menor que o total da venda (%).', v_pago, v_total;
  end if;
  v_troco := v_pago - v_total;
  if v_troco > v_dinheiro then
    raise exception 'O troco só pode ser dado sobre valor pago em dinheiro.';
  end if;

  for v_pg in
    select forma, sum(valor) as valor
      from jsonb_to_recordset(p_pagamentos) as x(forma text, valor numeric) group by forma
  loop
    v_liq := v_pg.valor - case when v_pg.forma = 'dinheiro' then v_troco else 0 end;
    if v_liq > 0 then
      insert into public.movimentacoes_caixa (caixa_id, tipo, forma_pagamento, valor, venda_id, colaborador_id)
        values (v_caixa, 'venda', v_pg.forma, v_liq, v_venda, v_colab);
    end if;
  end loop;

  update public.vendas set subtotal = v_subtotal, desconto = v_desc, total = v_total,
         valor_recebido = v_pago, troco = v_troco, pagamentos = p_pagamentos
   where id = v_venda;
  return v_venda;
end;
$$;

-- ---------- CANCELAMENTO / ESTORNO DE VENDA ----------
create or replace function public.cancelar_venda(p_venda_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_venda public.vendas%rowtype; v_colab uuid; v_caixa uuid; v_item record; v_mov record;
begin
  perform public.exigir_perfil('administrador','gerente');   -- regra 4
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo do cancelamento.'; end if;
  v_colab := public.meu_colaborador_id();
  select * into v_venda from public.vendas where id = p_venda_id for update;
  if not found then raise exception 'Venda não encontrada.'; end if;
  if v_venda.status <> 'concluida' then raise exception 'Esta venda já foi cancelada.'; end if;

  select id into v_caixa from public.caixas where id = v_venda.caixa_id and status = 'aberto';
  if v_caixa is null then
    select id into v_caixa from public.caixas where colaborador_id = v_colab and status = 'aberto';
  end if;
  if v_caixa is null then
    raise exception 'Abra um caixa para registrar o estorno financeiro.';
  end if;

  for v_item in select produto_id, quantidade from public.itens_venda where venda_id = p_venda_id loop
    insert into public.movimentacoes_estoque (produto_id, tipo, motivo, quantidade, venda_id, colaborador_id, observacao)
    values (v_item.produto_id, 'entrada', 'estorno', v_item.quantidade, p_venda_id, v_colab, 'Cancelamento da venda: ' || p_motivo);
  end loop;

  for v_mov in select forma_pagamento, valor from public.movimentacoes_caixa where venda_id = p_venda_id and tipo = 'venda' loop
    insert into public.movimentacoes_caixa (caixa_id, tipo, forma_pagamento, valor, venda_id, justificativa, colaborador_id)
    values (v_caixa, 'estorno', v_mov.forma_pagamento, v_mov.valor, p_venda_id, p_motivo, v_colab);
  end loop;

  update public.vendas set status = 'cancelada', cancelada_em = now(), cancelada_por = v_colab, motivo_cancelamento = p_motivo
   where id = p_venda_id;
end;
$$;

-- ---------- PONTO ----------
create or replace function public.iniciar_expediente()
returns uuid language plpgsql security definer set search_path = public as $$
declare v_colab uuid; v_id uuid;
begin
  perform public.exigir_perfil('administrador','gerente','operador_caixa','tecnico');
  v_colab := public.meu_colaborador_id();
  if exists (select 1 from public.registros_ponto where colaborador_id = v_colab and fim is null) then
    raise exception 'Seu expediente já foi iniciado.';
  end if;
  insert into public.registros_ponto (colaborador_id) values (v_colab) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.encerrar_expediente()
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.exigir_perfil('administrador','gerente','operador_caixa','tecnico');
  update public.registros_ponto set fim = now()
   where colaborador_id = public.meu_colaborador_id() and fim is null;
  if not found then raise exception 'Nenhum expediente em andamento.'; end if;
end;
$$;

-- ---------- DASHBOARD ----------
create or replace function public.dashboard_resumo(p_dias int default 7)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_gestor boolean;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ini date;
  r jsonb;
begin
  perform public.exigir_perfil('administrador','gerente','operador_caixa','tecnico');
  v_gestor := public.tem_perfil('administrador','gerente');
  p_dias := least(greatest(coalesce(p_dias, 7), 1), 90);
  v_ini := v_hoje - (p_dias - 1);

  r := jsonb_build_object(
    'produtos_cadastrados', (select count(*) from public.produtos where ativo),
    'estoque_baixo',        (select count(*) from public.produtos where ativo and quantidade_estoque <= estoque_minimo),
    'maquinas_ativas',      (select count(*) from public.maquinas_arcade where status = 'ativa'),
    'maquinas_manutencao',  (select count(*) from public.maquinas_arcade where status = 'em_manutencao')
  );

  if v_gestor then
    r := r || jsonb_build_object(
      'faturamento_dia', (select coalesce(sum(total), 0) from public.vendas
                           where status = 'concluida' and (criado_em at time zone 'America/Sao_Paulo')::date = v_hoje),
      'total_vendas',    (select count(*) from public.vendas
                           where status = 'concluida' and (criado_em at time zone 'America/Sao_Paulo')::date = v_hoje),
      'caixa_atual',     (select coalesce(sum(c.valor_inicial), 0) from public.caixas c where c.status = 'aberto')
                         + (select coalesce(sum(case when m.tipo in ('venda','suprimento') then m.valor else -m.valor end), 0)
                              from public.movimentacoes_caixa m join public.caixas c on c.id = m.caixa_id
                             where c.status = 'aberto'),
      'despesas_pendentes', (select coalesce(sum(valor), 0) from public.contas_financeiras
                              where tipo = 'pagar' and status in ('pendente','atrasado')),
      'faturamento_periodo', (
        select coalesce(jsonb_agg(jsonb_build_object('dia', d.dia, 'valor', coalesce(v.total, 0)) order by d.dia), '[]'::jsonb)
          from (select generate_series(v_ini, v_hoje, interval '1 day')::date as dia) d
          left join (select (criado_em at time zone 'America/Sao_Paulo')::date as dia, sum(total) as total
                       from public.vendas where status = 'concluida' group by 1) v on v.dia = d.dia
      ),
      'vendas_categoria', (
        select coalesce(jsonb_agg(jsonb_build_object('categoria', categoria, 'valor', valor) order by valor desc), '[]'::jsonb)
          from (select p.categoria, sum(i.subtotal) as valor
                  from public.itens_venda i
                  join public.vendas v on v.id = i.venda_id and v.status = 'concluida'
                  join public.produtos p on p.id = i.produto_id
                 where (v.criado_em at time zone 'America/Sao_Paulo')::date between v_ini and v_hoje
                 group by p.categoria) t
      ),
      'entradas_saidas', (
        select coalesce(jsonb_agg(jsonb_build_object('dia', d.dia, 'entradas', coalesce(f.entradas, 0), 'saidas', coalesce(f.saidas, 0)) order by d.dia), '[]'::jsonb)
          from (select generate_series(v_ini, v_hoje, interval '1 day')::date as dia) d
          left join (select dia, sum(entrada) as entradas, sum(saida) as saidas from public.vw_fluxo_financeiro group by dia) f on f.dia = d.dia
      ),
      'ultimas_movimentacoes', (
        select coalesce(jsonb_agg(t order by (t ->> 'em') desc), '[]'::jsonb) from (
          select t from (
            select jsonb_build_object('em', v.criado_em, 'tipo', 'Venda',
                     'descricao', 'Venda #' || v.numero || ' (' || v.status || ') - ' || c.nome_completo,
                     'valor', v.total) as t, v.criado_em as ts
              from public.vendas v join public.colaboradores c on c.id = v.colaborador_id
            union all
            select jsonb_build_object('em', m.criado_em, 'tipo', 'Estoque',
                     'descricao', initcap(m.tipo) || ' (' || m.motivo || '): ' || p.nome || ' x' || m.quantidade,
                     'valor', null), m.criado_em
              from public.movimentacoes_estoque m join public.produtos p on p.id = m.produto_id
             where m.motivo <> 'venda'
            union all
            select jsonb_build_object('em', x.criado_em, 'tipo', 'Caixa',
                     'descricao', initcap(x.tipo) || ' - ' || x.forma_pagamento, 'valor', x.valor), x.criado_em
              from public.movimentacoes_caixa x where x.tipo <> 'venda'
          ) u order by ts desc limit 10
        ) z
      )
    );
  end if;
  return r;
end;
$$;

-- ---------- RELATÓRIOS ----------
create or replace function public.relatorio(p_tipo text, p_inicio date, p_fim date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if p_tipo = 'historico_manutencao' then
    perform public.exigir_perfil('administrador','gerente','tecnico');
  else
    perform public.exigir_perfil('administrador','gerente');
  end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio then raise exception 'Período inválido.'; end if;

  if p_tipo = 'vendas' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.dia), '[]'::jsonb) into r from (
      select (v.criado_em at time zone 'America/Sao_Paulo')::date as dia, count(*) as qtd_vendas,
             sum(v.total) as total, sum(v.desconto) as descontos
        from public.vendas v
       where v.status = 'concluida'
         and (v.criado_em at time zone 'America/Sao_Paulo')::date between p_inicio and p_fim
       group by 1) t;
  elsif p_tipo = 'mais_vendidos' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.quantidade desc), '[]'::jsonb) into r from (
      select p.nome as produto, p.categoria, sum(i.quantidade) as quantidade, sum(i.subtotal) as total
        from public.itens_venda i
        join public.vendas v on v.id = i.venda_id and v.status = 'concluida'
        join public.produtos p on p.id = i.produto_id
       where (v.criado_em at time zone 'America/Sao_Paulo')::date between p_inicio and p_fim
       group by p.nome, p.categoria order by sum(i.quantidade) desc limit 50) t;
  elsif p_tipo = 'mov_estoque' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.criado_em desc), '[]'::jsonb) into r from (
      select m.criado_em, p.nome as produto, m.tipo, m.motivo, m.quantidade, c.nome_completo as responsavel
        from public.movimentacoes_estoque m
        join public.produtos p on p.id = m.produto_id
        join public.colaboradores c on c.id = m.colaborador_id
       where (m.criado_em at time zone 'America/Sao_Paulo')::date between p_inicio and p_fim
       order by m.criado_em desc limit 500) t;
  elsif p_tipo = 'entradas_saidas' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.dia), '[]'::jsonb) into r from (
      select dia, sum(entrada) as entradas, sum(saida) as saidas, sum(entrada) - sum(saida) as saldo
        from public.vw_fluxo_financeiro where dia between p_inicio and p_fim group by dia) t;
  elsif p_tipo = 'fluxo_caixa' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.dia), '[]'::jsonb) into r from (
      select (m.criado_em at time zone 'America/Sao_Paulo')::date as dia,
             sum(case when m.tipo = 'venda' then m.valor else 0 end) as vendas_caixa,
             sum(case when m.tipo = 'suprimento' then m.valor else 0 end) as suprimentos,
             sum(case when m.tipo = 'sangria' then m.valor else 0 end) as sangrias,
             sum(case when m.tipo = 'estorno' then m.valor else 0 end) as estornos,
             sum(case when m.tipo in ('venda','suprimento') then m.valor else -m.valor end) as saldo
        from public.movimentacoes_caixa m
       where (m.criado_em at time zone 'America/Sao_Paulo')::date between p_inicio and p_fim
       group by 1) t;
  elsif p_tipo = 'despesas' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.data_vencimento), '[]'::jsonb) into r from (
      select descricao, categoria, valor, data_vencimento, data_pagamento,
             case when status = 'pendente' and data_vencimento < current_date then 'atrasado' else status end as status
        from public.contas_financeiras
       where tipo = 'pagar' and data_vencimento between p_inicio and p_fim) t;
  elsif p_tipo = 'fechamentos' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.fechado_em desc), '[]'::jsonb) into r from (
      select c.nome_completo as operador, k.aberto_em, k.fechado_em, k.valor_inicial, k.diferenca, k.justificativa_divergencia as justificativa
        from public.caixas k join public.colaboradores c on c.id = k.colaborador_id
       where k.status = 'fechado'
         and (k.fechado_em at time zone 'America/Sao_Paulo')::date between p_inicio and p_fim) t;
  elsif p_tipo = 'historico_manutencao' then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.data desc), '[]'::jsonb) into r from (
      select m.criado_em as data, mq.nome_jogo as maquina, mq.numero_patrimonio as patrimonio, p.nome as peca,
             m.quantidade, c.nome_completo as responsavel, m.observacao
        from public.movimentacoes_estoque m
        join public.maquinas_arcade mq on mq.id = m.maquina_id
        join public.produtos p on p.id = m.produto_id
        join public.colaboradores c on c.id = m.colaborador_id
       where m.motivo = 'manutencao'
         and (m.criado_em at time zone 'America/Sao_Paulo')::date between p_inicio and p_fim) t;
  else
    raise exception 'Relatório desconhecido.';
  end if;
  return r;
end;
$$;

-- =====================================================================
-- ROW LEVEL SECURITY
-- Escritas críticas só acontecem pelas RPCs acima (security definer).
-- Nenhuma tabela tem política de DELETE.
-- =====================================================================
alter table public.perfis_acesso         enable row level security;
alter table public.colaboradores         enable row level security;
alter table public.fornecedores          enable row level security;
alter table public.produtos              enable row level security;
alter table public.maquinas_arcade       enable row level security;
alter table public.escalas_turnos        enable row level security;
alter table public.registros_ponto       enable row level security;
alter table public.caixas                enable row level security;
alter table public.movimentacoes_caixa   enable row level security;
alter table public.vendas                enable row level security;
alter table public.itens_venda           enable row level security;
alter table public.movimentacoes_estoque enable row level security;
alter table public.contas_financeiras    enable row level security;

-- perfis_acesso
drop policy if exists "perfis: leitura" on public.perfis_acesso;
create policy "perfis: leitura" on public.perfis_acesso for select to authenticated using (true);

-- colaboradores
drop policy if exists "colab: leitura" on public.colaboradores;
create policy "colab: leitura" on public.colaboradores for select to authenticated
  using (user_id = auth.uid() or public.tem_perfil('administrador','gerente'));
drop policy if exists "colab: admin atualiza" on public.colaboradores;
create policy "colab: admin atualiza" on public.colaboradores for update to authenticated
  using (public.tem_perfil('administrador')) with check (public.tem_perfil('administrador'));

-- fornecedores
drop policy if exists "forn: leitura" on public.fornecedores;
create policy "forn: leitura" on public.fornecedores for select to authenticated
  using (public.tem_perfil('administrador','gerente'));
drop policy if exists "forn: insere" on public.fornecedores;
create policy "forn: insere" on public.fornecedores for insert to authenticated
  with check (public.tem_perfil('administrador','gerente'));
drop policy if exists "forn: atualiza" on public.fornecedores;
create policy "forn: atualiza" on public.fornecedores for update to authenticated
  using (public.tem_perfil('administrador','gerente')) with check (public.tem_perfil('administrador','gerente'));

-- produtos
drop policy if exists "prod: leitura" on public.produtos;
create policy "prod: leitura" on public.produtos for select to authenticated
  using (public.meu_colaborador_id() is not null);
drop policy if exists "prod: insere" on public.produtos;
create policy "prod: insere" on public.produtos for insert to authenticated
  with check (public.tem_perfil('administrador','gerente'));
drop policy if exists "prod: atualiza" on public.produtos;
create policy "prod: atualiza" on public.produtos for update to authenticated
  using (public.tem_perfil('administrador','gerente')) with check (public.tem_perfil('administrador','gerente'));

-- maquinas_arcade
drop policy if exists "maq: leitura" on public.maquinas_arcade;
create policy "maq: leitura" on public.maquinas_arcade for select to authenticated
  using (public.meu_colaborador_id() is not null);
drop policy if exists "maq: insere" on public.maquinas_arcade;
create policy "maq: insere" on public.maquinas_arcade for insert to authenticated
  with check (public.tem_perfil('administrador','gerente','tecnico'));
drop policy if exists "maq: atualiza" on public.maquinas_arcade;
create policy "maq: atualiza" on public.maquinas_arcade for update to authenticated
  using (public.tem_perfil('administrador','gerente','tecnico')) with check (public.tem_perfil('administrador','gerente','tecnico'));

-- escalas_turnos
drop policy if exists "esc: leitura" on public.escalas_turnos;
create policy "esc: leitura" on public.escalas_turnos for select to authenticated
  using (colaborador_id = public.meu_colaborador_id() or public.tem_perfil('administrador','gerente'));
drop policy if exists "esc: insere" on public.escalas_turnos;
create policy "esc: insere" on public.escalas_turnos for insert to authenticated
  with check (public.tem_perfil('administrador','gerente'));
drop policy if exists "esc: atualiza" on public.escalas_turnos;
create policy "esc: atualiza" on public.escalas_turnos for update to authenticated
  using (public.tem_perfil('administrador','gerente')) with check (public.tem_perfil('administrador','gerente'));

-- registros_ponto (escrita só por RPC)
drop policy if exists "ponto: leitura" on public.registros_ponto;
create policy "ponto: leitura" on public.registros_ponto for select to authenticated
  using (colaborador_id = public.meu_colaborador_id() or public.tem_perfil('administrador','gerente'));

-- caixas e movimentações de caixa (escrita só por RPC)
drop policy if exists "caixa: leitura" on public.caixas;
create policy "caixa: leitura" on public.caixas for select to authenticated
  using (colaborador_id = public.meu_colaborador_id() or public.tem_perfil('administrador','gerente'));
drop policy if exists "movcaixa: leitura" on public.movimentacoes_caixa;
create policy "movcaixa: leitura" on public.movimentacoes_caixa for select to authenticated
  using (exists (select 1 from public.caixas c where c.id = movimentacoes_caixa.caixa_id));

-- vendas e itens (escrita só por RPC)
drop policy if exists "vendas: leitura" on public.vendas;
create policy "vendas: leitura" on public.vendas for select to authenticated
  using (colaborador_id = public.meu_colaborador_id() or public.tem_perfil('administrador','gerente'));
drop policy if exists "itens: leitura" on public.itens_venda;
create policy "itens: leitura" on public.itens_venda for select to authenticated
  using (exists (select 1 from public.vendas v where v.id = itens_venda.venda_id));

-- movimentacoes_estoque (escrita só por RPC)
drop policy if exists "movest: leitura" on public.movimentacoes_estoque;
create policy "movest: leitura" on public.movimentacoes_estoque for select to authenticated
  using (public.tem_perfil('administrador','gerente','tecnico') or colaborador_id = public.meu_colaborador_id());

-- contas_financeiras
drop policy if exists "contas: leitura" on public.contas_financeiras;
create policy "contas: leitura" on public.contas_financeiras for select to authenticated
  using (public.tem_perfil('administrador','gerente'));
drop policy if exists "contas: insere" on public.contas_financeiras;
create policy "contas: insere" on public.contas_financeiras for insert to authenticated
  with check (public.tem_perfil('administrador','gerente'));
drop policy if exists "contas: atualiza" on public.contas_financeiras;
create policy "contas: atualiza" on public.contas_financeiras for update to authenticated
  using (public.tem_perfil('administrador','gerente')) with check (public.tem_perfil('administrador','gerente'));

-- ========== PERMISSÕES DE EXECUÇÃO ==========
revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;
revoke all on public.vw_fluxo_financeiro from anon;
