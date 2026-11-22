-- ESSENZA: catálogo público para usuarios autenticados y flujo de pedidos.
-- Ejecutar una sola vez en Supabase SQL Editor del proyecto ESSENZA.

-- Todos los usuarios autenticados pueden consultar el catálogo.
drop policy if exists "Essenza admins can read products" on public.products;
drop policy if exists "Authenticated users can read catalog products" on public.products;
create policy "Authenticated users can read catalog products"
on public.products for select to authenticated
using (true);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete cascade,
  buyer_email text not null,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  unit_price numeric(12,2) not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0),
  status text not null default 'pending'
    check (status in ('pending','in_progress','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.orders enable row level security;

drop policy if exists "Buyers and admins can read Essenza orders" on public.orders;
create policy "Buyers and admins can read Essenza orders"
on public.orders for select to authenticated
using (
  buyer_id = (select auth.uid())
  or exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  )
);

drop policy if exists "Buyers can create their own Essenza orders" on public.orders;
create policy "Buyers can create their own Essenza orders"
on public.orders for insert to authenticated
with check (
  buyer_id = (select auth.uid())
  and buyer_email = coalesce((select auth.jwt() ->> 'email'), '')
  and status = 'pending'
  and exists (
    select 1 from public.products p
    where p.id = product_id and p.stock >= quantity
  )
);

drop policy if exists "Only Essenza admins can update orders" on public.orders;
create policy "Only Essenza admins can update orders"
on public.orders for update to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  )
)
with check (
  exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  )
);

grant select on public.products to authenticated;
grant select, insert, update on public.orders to authenticated;
