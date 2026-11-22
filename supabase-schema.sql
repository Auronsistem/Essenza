-- ESSENZA: esquema completo para el proyecto Supabase independiente.
-- No contiene service_role ni claves secretas.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'user' check (role in ('admin','user')),
  created_at timestamptz not null default now()
);

create schema if not exists private;
grant usage on schema private to authenticated;

-- El perfil y el rol se crean solo cuando el correo ya fue verificado.
create or replace function private.create_essenza_profile()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare assigned_role text;
begin
  if new.email_confirmed_at is null then return new; end if;
  perform pg_advisory_xact_lock(721904222);
  if not exists (select 1 from public.profiles) then assigned_role := 'admin';
  else assigned_role := 'user'; end if;
  insert into public.profiles(id,email,role)
  values(new.id,lower(new.email),assigned_role)
  on conflict(id) do update set email=excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_essenza on auth.users;
drop trigger if exists on_auth_user_confirmed_essenza on auth.users;
create trigger on_auth_user_created_essenza
after insert on auth.users
for each row when (new.email_confirmed_at is not null)
execute function private.create_essenza_profile();
create trigger on_auth_user_confirmed_essenza
after update of email_confirmed_at on auth.users
for each row when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
execute function private.create_essenza_profile();

-- Funciones internas para políticas RLS de administrador.
create or replace function private.is_essenza_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id=(select auth.uid()) and p.role='admin'
  );
$$;
revoke all on function private.is_essenza_admin() from public;
grant execute on function private.is_essenza_admin() to authenticated;

create or replace function private.is_essenza_admin_id(candidate uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.profiles p
    where p.id=candidate and p.role='admin'
  );
$$;
revoke all on function private.is_essenza_admin_id(uuid) from public;
grant execute on function private.is_essenza_admin_id(uuid) to authenticated;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price numeric(12,2) not null check(price >= 0),
  stock integer not null default 0 check(stock >= 0),
  description text,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete cascade,
  buyer_email text,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  unit_price numeric(12,2) not null,
  quantity integer not null check(quantity > 0),
  status text not null default 'pending'
    check(status in ('pending','in_progress','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check(char_length(trim(body)) between 1 and 4000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint messages_different_users check(sender_id <> recipient_id)
);
create index if not exists messages_sender_created_idx on public.messages(sender_id,created_at);
create index if not exists messages_recipient_created_idx on public.messages(recipient_id,created_at);

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.messages enable row level security;

-- Profiles
drop policy if exists "Essenza users read own profile" on public.profiles;
create policy "Essenza users read own profile"
on public.profiles for select to authenticated using((select auth.uid())=id);
drop policy if exists "Essenza admins can read all profiles" on public.profiles;
create policy "Essenza admins can read all profiles"
on public.profiles for select to authenticated using(private.is_essenza_admin());
drop policy if exists "Authenticated users can find Essenza support profile" on public.profiles;
create policy "Authenticated users can find Essenza support profile"
on public.profiles for select to authenticated using(role='admin');

-- Catalog: all authenticated buyers can see published products.
drop policy if exists "Essenza admins can read products" on public.products;
drop policy if exists "Essenza admin reads products" on public.products;
drop policy if exists "Authenticated users can read Essenza catalog" on public.products;
create policy "Authenticated users can read Essenza catalog"
on public.products for select to authenticated using(true);
drop policy if exists "Essenza admin inserts products" on public.products;
create policy "Essenza admin inserts products"
on public.products for insert to authenticated
with check(created_by=(select auth.uid()) and private.is_essenza_admin());

-- Orders
drop policy if exists "buyers create own orders" on public.orders;
create policy "buyers create own orders" on public.orders for insert to authenticated
with check(buyer_id=(select auth.uid()));
drop policy if exists "buyers and admins read orders" on public.orders;
create policy "buyers and admins read orders" on public.orders for select to authenticated
using(buyer_id=(select auth.uid()) or private.is_essenza_admin());
drop policy if exists "admins update orders" on public.orders;
create policy "admins update orders" on public.orders for update to authenticated
using(private.is_essenza_admin()) with check(private.is_essenza_admin());

-- Messages: buyers can talk only with the ESSENZA administrator.
drop policy if exists "Users read their Essenza conversations" on public.messages;
create policy "Users read their Essenza conversations"
on public.messages for select to authenticated
using(sender_id=(select auth.uid()) or recipient_id=(select auth.uid()));
drop policy if exists "Users send Essenza messages to admin" on public.messages;
create policy "Users send Essenza messages to admin"
on public.messages for insert to authenticated
with check(
  sender_id=(select auth.uid())
  and (private.is_essenza_admin() or private.is_essenza_admin_id(recipient_id))
);

grant select on public.profiles to authenticated;
grant select,insert on public.products to authenticated;
grant select,insert,update on public.orders to authenticated;
grant select,insert on public.messages to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

notify pgrst,'reload schema';
