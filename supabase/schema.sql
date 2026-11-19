-- ERP base - rode este arquivo no SQL Editor do Supabase.

-- ========== PERFIS (ligados ao auth.users) ==========
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'user' check (role in ('admin', 'manager', 'user')),
  sector_id uuid,
  created_at timestamptz not null default now()
);

-- Cria o perfil automaticamente quando alguém se cadastra
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ========== SETORES ==========
create table if not exists public.sectors (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz not null default now()
);

alter table public.profiles
  drop constraint if exists profiles_sector_fk,
  add constraint profiles_sector_fk
  foreign key (sector_id) references public.sectors(id) on delete set null;

-- ========== PRODUTOS / ESTOQUE ==========
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  name text not null,
  sector_id uuid references public.sectors(id) on delete set null,
  unit text not null default 'un',
  quantity numeric not null default 0,
  min_quantity numeric not null default 0,
  price numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  type text not null check (type in ('in', 'out')),
  quantity numeric not null check (quantity > 0),
  note text,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);

-- Atualiza o saldo do produto a cada movimentação
create or replace function public.apply_stock_movement()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.type = 'in' then
    update public.products set quantity = quantity + new.quantity
    where id = new.product_id;
  else
    update public.products set quantity = quantity - new.quantity
    where id = new.product_id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_stock_movement on public.stock_movements;
create trigger on_stock_movement
  after insert on public.stock_movements
  for each row execute function public.apply_stock_movement();

-- ========== SEGURANÇA (RLS) ==========
-- Base simples: qualquer usuário logado lê e escreve.
-- Refine depois usando profiles.role / profiles.sector_id.
alter table public.profiles enable row level security;
alter table public.sectors enable row level security;
alter table public.products enable row level security;
alter table public.stock_movements enable row level security;

create policy "profiles: ler o próprio" on public.profiles
  for select to authenticated using (id = auth.uid());
create policy "profiles: editar o próprio" on public.profiles
  for update to authenticated using (id = auth.uid());

create policy "sectors: autenticados" on public.sectors
  for all to authenticated using (true) with check (true);
create policy "products: autenticados" on public.products
  for all to authenticated using (true) with check (true);
create policy "stock_movements: autenticados" on public.stock_movements
  for all to authenticated using (true) with check (true);
