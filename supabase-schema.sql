-- ESSENZA: ejecutar únicamente en el proyecto Supabase independiente de este sistema.
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 email text,
 role text not null default 'user' check (role in ('admin','user')),
 created_at timestamptz not null default now()
);
create schema if not exists private;
create or replace function private.create_essenza_profile()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare assigned_role text;
begin
 perform pg_advisory_xact_lock(721904222);
 if not exists (select 1 from public.profiles) then assigned_role := 'admin';
 else assigned_role := 'user'; end if;
 insert into public.profiles(id,email,role) values(new.id,new.email,assigned_role)
 on conflict(id) do nothing;
 return new;
end;
$$;
drop trigger if exists on_auth_user_created_essenza on auth.users;
create trigger on_auth_user_created_essenza after insert on auth.users
for each row execute function private.create_essenza_profile();
create table if not exists public.products (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 price numeric(12,2) not null check(price >= 0),
 stock integer not null default 0 check(stock >= 0),
 description text,
 created_by uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
alter table public.products enable row level security;
drop policy if exists "Users can read own Essenza profile" on public.profiles;
create policy "Users can read own Essenza profile" on public.profiles for select to authenticated using((select auth.uid())=id);
drop policy if exists "Essenza admins can read products" on public.products;
create policy "Essenza admins can read products" on public.products for select to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
drop policy if exists "Essenza admins can insert products" on public.products;
create policy "Essenza admins can insert products" on public.products for insert to authenticated with check(created_by=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
grant select on public.profiles to authenticated;
grant select,insert on public.products to authenticated;
