-- =====================================================================
-- ERP Fliperamada TI - reparo de banco já existente
--
-- Use este arquivo quando o projeto já tinha uma versão antiga do schema,
-- quando o usuário existe em auth.users mas não em colaboradores, ou quando
-- o login retorna "colaborador inativo ou não cadastrado".
--
-- Este script NÃO apaga public.profiles nem outras tabelas antigas.
-- O código atual usa somente:
--   auth.users -> public.colaboradores -> public.perfis_acesso
-- Faça backup antes de qualquer alteração em banco com dados reais.
-- =====================================================================

-- 1) Reforça o catálogo oficial de perfis.
insert into public.perfis_acesso
  (codigo, nome, descricao, pode_desconto, pode_estorno, pode_relatorios)
values
  ('administrador',  'Administrador',     'Acesso completo ao sistema', true,  true,  true),
  ('gerente',        'Gerente',           'Operações, estornos e relatórios', true, true, true),
  ('operador_caixa', 'Operador de Caixa', 'PDV e funcionalidades de caixa', false, false, false),
  ('tecnico',        'Técnico',           'Máquinas e saídas de peças para manutenção', false, false, false)
on conflict (codigo) do update set
  nome = excluded.nome,
  descricao = excluded.descricao,
  pode_desconto = excluded.pode_desconto,
  pode_estorno = excluded.pode_estorno,
  pode_relatorios = excluded.pode_relatorios;

-- 2) Garante a função oficial de cadastro. O primeiro colaborador vira admin;
-- os demais aguardam ativação pelo administrador.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_primeiro boolean;
begin
  select not exists (select 1 from public.colaboradores) into v_primeiro;

  insert into public.colaboradores
    (user_id, nome_completo, email, perfil_id, ativo, data_admissao)
  values
    (
      new.id,
      coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(new.email, '@', 1)),
      new.email,
      case when v_primeiro then 'administrador' else 'operador_caixa' end,
      v_primeiro,
      case when v_primeiro then current_date else null end
    )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- 3) Repara usuários criados antes do trigger atual.
-- Se ainda não havia nenhum colaborador, o usuário Auth mais antigo vira admin.
with usuarios as (
  select
    u.id,
    u.email,
    u.raw_user_meta_data,
    u.created_at,
    row_number() over (order by u.created_at, u.id) as ordem,
    exists (select 1 from public.colaboradores) as ja_havia_colaborador
  from auth.users u
  where not exists (
    select 1 from public.colaboradores c where c.user_id = u.id
  )
)
insert into public.colaboradores
  (user_id, nome_completo, email, perfil_id, ativo, data_admissao)
select
  id,
  coalesce(nullif(raw_user_meta_data ->> 'full_name', ''), split_part(email, '@', 1)),
  email,
  case when not ja_havia_colaborador and ordem = 1 then 'administrador' else 'operador_caixa' end,
  case when not ja_havia_colaborador and ordem = 1 then true else false end,
  case when not ja_havia_colaborador and ordem = 1 then current_date else null end
from usuarios
on conflict (user_id) do nothing;

-- 4) Corrige as permissões SQL necessárias para o papel autenticado.
grant usage on schema public to authenticated;
grant select on
  public.perfis_acesso,
  public.colaboradores,
  public.fornecedores,
  public.produtos,
  public.maquinas_arcade,
  public.escalas_turnos,
  public.registros_ponto,
  public.caixas,
  public.movimentacoes_caixa,
  public.vendas,
  public.itens_venda,
  public.movimentacoes_estoque,
  public.contas_financeiras
 to authenticated;

grant insert, update on
  public.fornecedores,
  public.produtos,
  public.maquinas_arcade,
  public.escalas_turnos,
  public.contas_financeiras
 to authenticated;

grant select on public.vw_fluxo_financeiro to authenticated;
grant execute on all functions in schema public to authenticated;

-- 5) Diagnóstico final. Deve listar seu usuário com perfil e situação.
select
  u.id as auth_user_id,
  u.email as auth_email,
  c.id as colaborador_id,
  c.nome_completo,
  c.perfil_id,
  c.ativo
from auth.users u
left join public.colaboradores c on c.user_id = u.id
order by u.created_at;
