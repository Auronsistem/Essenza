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

create or replace function private.is_essenza_profile_id(candidate uuid)
returns boolean language sql stable security definer set search_path = ''
as $
  select (select auth.uid()) is not null
    and exists(select 1 from public.profiles p where p.id=candidate);
$;
revoke all on function private.is_essenza_profile_id(uuid) from public;
grant execute on function private.is_essenza_profile_id(uuid) to authenticated;

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
create index if not exists orders_buyer_id_idx on public.orders(buyer_id);
create index if not exists orders_product_id_idx on public.orders(product_id);
create index if not exists products_created_by_idx on public.products(created_by);

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.messages enable row level security;

-- Profiles
drop policy if exists "Essenza users read own profile" on public.profiles;
create policy "Essenza users read own profile"
on public.profiles for select to authenticated using((select auth.uid())=id);

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



-- ESSENZA private user-to-user messaging. Search only by exact email.
create or replace function public.find_essenza_user_by_email(p_email text)
returns table(user_id uuid,user_email text)
language sql stable security definer set search_path = ''
as $
  select p.id,p.email from public.profiles p
  where (select auth.uid()) is not null
    and p.id <> (select auth.uid())
    and lower(p.email)=lower(trim(p_email))
  limit 1;
$;
revoke all on function public.find_essenza_user_by_email(text) from public,anon;
grant execute on function public.find_essenza_user_by_email(text) to authenticated;

create or replace function public.get_essenza_conversations()
returns table(user_id uuid,user_email text,last_message text,last_at timestamptz)
language sql stable security definer set search_path = ''
as $
  select p.id,p.email,latest.body,latest.created_at
  from (
    select distinct case when m.sender_id=(select auth.uid()) then m.recipient_id else m.sender_id end as other_id
    from public.messages m
    where (select auth.uid()) is not null
      and (m.sender_id=(select auth.uid()) or m.recipient_id=(select auth.uid()))
  ) contacts
  join public.profiles p on p.id=contacts.other_id
  cross join lateral (
    select m.body,m.created_at from public.messages m
    where (m.sender_id=(select auth.uid()) and m.recipient_id=contacts.other_id)
       or (m.sender_id=contacts.other_id and m.recipient_id=(select auth.uid()))
    order by m.created_at desc limit 1
  ) latest
  order by latest.created_at desc;
$;
revoke all on function public.get_essenza_conversations() from public,anon;
grant execute on function public.get_essenza_conversations() to authenticated;

drop policy if exists "Users send Essenza messages to admin" on public.messages;
drop policy if exists "Users send private Essenza messages" on public.messages;
create policy "Users send private Essenza messages"
on public.messages for insert to authenticated
with check (
  sender_id=(select auth.uid())
  and recipient_id<>(select auth.uid())
  and private.is_essenza_profile_id(recipient_id)
);
drop policy if exists "Recipients mark Essenza messages read" on public.messages;
create policy "Recipients mark Essenza messages read"
on public.messages for update to authenticated
using(recipient_id=(select auth.uid()))
with check(recipient_id=(select auth.uid()));
grant update(read_at) on public.messages to authenticated;

-- Voice and video call invitations.
create table if not exists public.call_sessions (
  id uuid primary key default gen_random_uuid(),
  caller_id uuid not null references auth.users(id) on delete cascade,
  callee_id uuid not null references auth.users(id) on delete cascade,
  call_type text not null check(call_type in ('audio','video')),
  status text not null default 'ringing'
    check(status in ('ringing','accepted','declined','cancelled','ended')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  ended_at timestamptz,
  constraint essenza_call_different_users check(caller_id<>callee_id)
);
create index if not exists essenza_calls_callee_created_idx on public.call_sessions(callee_id,created_at desc);
create index if not exists essenza_calls_caller_created_idx on public.call_sessions(caller_id,created_at desc);
alter table public.call_sessions enable row level security;
drop policy if exists "Participants read their Essenza calls" on public.call_sessions;
create policy "Participants read their Essenza calls"
on public.call_sessions for select to authenticated
using(caller_id=(select auth.uid()) or callee_id=(select auth.uid()));
drop policy if exists "Users create Essenza calls" on public.call_sessions;
create policy "Users create Essenza calls"
on public.call_sessions for insert to authenticated
with check (
  caller_id=(select auth.uid())
  and status='ringing'
  and private.is_essenza_profile_id(callee_id)
);
grant select,insert on public.call_sessions to authenticated;

create or replace function public.set_essenza_call_status(p_call_id uuid,p_status text)
returns public.call_sessions
language plpgsql security definer set search_path = ''
as $
declare c public.call_sessions; actor uuid := (select auth.uid());
begin
  if actor is null then raise exception 'Debes iniciar sesión.'; end if;
  select * into c from public.call_sessions where id=p_call_id for update;
  if not found then raise exception 'No se encontró la llamada.'; end if;
  if p_status in ('accepted','declined') then
    if actor<>c.callee_id or c.status<>'ringing' then raise exception 'No tienes permiso para responder esta llamada.'; end if;
  elsif p_status='cancelled' then
    if actor<>c.caller_id or c.status<>'ringing' then raise exception 'No puedes cancelar esta llamada.'; end if;
  elsif p_status='ended' then
    if actor not in (c.caller_id,c.callee_id) or c.status not in ('ringing','accepted') then raise exception 'No puedes finalizar esta llamada.'; end if;
  else raise exception 'Estado de llamada no válido.';
  end if;
  update public.call_sessions
  set status=p_status,
      accepted_at=case when p_status='accepted' then now() else accepted_at end,
      ended_at=case when p_status in ('declined','cancelled','ended') then now() else ended_at end
  where id=p_call_id returning * into c;
  return c;
end;
$;
revoke all on function public.set_essenza_call_status(uuid,text) from public,anon;
grant execute on function public.set_essenza_call_status(uuid,text) to authenticated;

create or replace function public.get_essenza_call_contact(p_call_id uuid)
returns table(user_id uuid,user_email text)
language sql stable security definer set search_path = ''
as $
  select p.id,p.email from public.call_sessions c
  join public.profiles p on p.id=case
    when c.caller_id=(select auth.uid()) then c.callee_id else c.caller_id end
  where c.id=p_call_id
    and (c.caller_id=(select auth.uid()) or c.callee_id=(select auth.uid()))
  limit 1;
$;
revoke all on function public.get_essenza_call_contact(uuid) from public,anon;
grant execute on function public.get_essenza_call_contact(uuid) to authenticated;

-- Private Realtime signaling: only the two participants can exchange WebRTC offers/answers/ICE.
drop policy if exists "Essenza call participants receive signals" on realtime.messages;
create policy "Essenza call participants receive signals"
on realtime.messages for select to authenticated
using(exists(
  select 1 from public.call_sessions c
  where realtime.topic()='essenza-call:'||c.id::text
    and (c.caller_id=(select auth.uid()) or c.callee_id=(select auth.uid()))
));
drop policy if exists "Essenza call participants send signals" on realtime.messages;
create policy "Essenza call participants send signals"
on realtime.messages for insert to authenticated
with check(exists(
  select 1 from public.call_sessions c
  where realtime.topic()='essenza-call:'||c.id::text
    and (c.caller_id=(select auth.uid()) or c.callee_id=(select auth.uid()))
));

do $
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='call_sessions') then
    alter publication supabase_realtime add table public.call_sessions;
  end if;
end $;
notify pgrst,'reload schema';


-- Inventario atomico y notificaciones de ESSENZA.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('new_order','stock_depleted','order_ready')),
  title text not null,
  body text not null,
  order_id uuid references public.orders(id) on delete set null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists notifications_user_created_idx on public.notifications(user_id,created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "Users read own Essenza notifications" on public.notifications;
create policy "Users read own Essenza notifications" on public.notifications for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists "Users mark own Essenza notifications read" on public.notifications;
create policy "Users mark own Essenza notifications read" on public.notifications for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
grant select on public.notifications to authenticated;
grant update(read_at) on public.notifications to authenticated;

drop policy if exists "buyers create own orders" on public.orders;
revoke insert on public.orders from authenticated;
create or replace function public.create_essenza_order(p_product_id uuid,p_quantity integer)
returns public.orders language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid()); product_row public.products; created_order public.orders;
begin
 if actor is null then raise exception 'Debes iniciar sesión para solicitar un perfume.'; end if;
 if p_quantity is null or p_quantity<1 or p_quantity>100 then raise exception 'La cantidad solicitada no es válida.'; end if;
 select * into product_row from public.products where id=p_product_id for update;
 if not found then raise exception 'Este perfume ya no está disponible.'; end if;
 if product_row.stock<p_quantity then raise exception 'Stock insuficiente. Disponibles: %.',product_row.stock; end if;
 update public.products set stock=stock-p_quantity where id=p_product_id;
 insert into public.orders(buyer_id,buyer_email,product_id,product_name,unit_price,quantity,status)
 values(actor,coalesce((select auth.jwt()->>'email'),''),product_row.id,product_row.name,product_row.price,p_quantity,'pending')
 returning * into created_order;
 return created_order;
end; $$;
revoke all on function public.create_essenza_order(uuid,integer) from public,anon;
grant execute on function public.create_essenza_order(uuid,integer) to authenticated;

drop policy if exists "Essenza admin deletes products" on public.products;
create policy "Essenza admin deletes products" on public.products for delete to authenticated using(private.is_essenza_admin());
grant delete on public.products to authenticated;

create or replace function private.notify_essenza_order_events()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare admin_user uuid; remaining_stock integer;
begin
 if tg_op='INSERT' then
  select id into admin_user from public.profiles where role='admin' order by created_at asc limit 1;
  if admin_user is not null then
   insert into public.notifications(user_id,type,title,body,order_id)
   values(admin_user,'new_order','Nuevo pedido en ESSENZA',coalesce(new.buyer_email,'Un comprador')||' solicitó '||new.quantity::text||' unidad(es) de '||new.product_name||'.',new.id);
  end if;
  if new.product_id is not null then
   select stock into remaining_stock from public.products where id=new.product_id;
   if remaining_stock=0 and admin_user is not null then
    insert into public.notifications(user_id,type,title,body,order_id)
    values(admin_user,'stock_depleted','Perfume sin stock','“'||new.product_name||'” llegó a 0 unidades después de este pedido.',new.id);
   end if;
  end if;
 elsif tg_op='UPDATE' and old.status is distinct from new.status and new.status='completed' then
  insert into public.notifications(user_id,type,title,body,order_id)
  values(new.buyer_id,'order_ready','Tu pedido está listo','Tu pedido de '||new.product_name||' está listo.',new.id);
 end if;
 return new;
end; $$;
drop trigger if exists essenza_notify_order_insert on public.orders;
create trigger essenza_notify_order_insert after insert on public.orders for each row execute function private.notify_essenza_order_events();
drop trigger if exists essenza_notify_order_ready on public.orders;
create trigger essenza_notify_order_ready after update of status on public.orders for each row execute function private.notify_essenza_order_events();

do $$
begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='notifications') then alter publication supabase_realtime add table public.notifications; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='orders') then alter publication supabase_realtime add table public.orders; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='products') then alter publication supabase_realtime add table public.products; end if;
end $$;
