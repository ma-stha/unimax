-- UNIMAX BILLING v0.1 — Run once in Supabase SQL Editor.
-- Only manually invited Supabase Auth users may access app data.
create table if not exists public.staff (
 user_id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default 'Staff',
 role text not null default 'staff' check (role in ('admin','staff'))
);
create table if not exists public.settings (
 id int primary key default 1 check(id=1),
 company_name text not null default 'UNIMAX TRADERS',
 address text not null default 'Urlabari, Morang, Nepal',
 phone text not null default '', pan text not null default '',
 invoice_prefix text not null default 'UM-',
 footer_text text not null default 'Thank you for your business.',
 updated_at timestamptz not null default now()
);
insert into public.settings(id) values(1) on conflict do nothing;
create table if not exists public.customers (
 id uuid primary key default gen_random_uuid(), name text not null,
 address text not null default '', phone text not null default '', pan text not null default '',
 created_at timestamptz not null default now()
);
create table if not exists public.products (
 id uuid primary key default gen_random_uuid(), sku text not null default '', name text not null,
 unit text not null default 'pcs', price numeric(12,2) not null default 0 check(price>=0),
 created_at timestamptz not null default now()
);
create table if not exists public.invoice_counter(id int primary key default 1 check(id=1), last_number bigint not null default 0);
insert into public.invoice_counter(id,last_number) values(1,0) on conflict do nothing;
create table if not exists public.invoices (
 id uuid primary key default gen_random_uuid(),
 invoice_number bigint unique,
 status text not null default 'draft' check(status in ('draft','final','void')),
 customer_id uuid references public.customers(id) on delete set null,
 customer_snapshot jsonb not null default '{}'::jsonb,
 items jsonb not null default '[]'::jsonb,
 issued_on date not null default current_date,
 discount numeric(12,2) not null default 0 check(discount>=0),
 tax_rate numeric(6,3) not null default 0 check(tax_rate>=0 and tax_rate<=100),
 paid numeric(12,2) not null default 0 check(paid>=0),
 notes text not null default '',
 subtotal numeric(12,2) not null default 0,
 total numeric(12,2) not null default 0,
 issued_snapshot jsonb,
 void_reason text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), finalized_at timestamptz,
 voided_at timestamptz,
 constraint invoice_number_status check ((status='draft' and invoice_number is null) or (status in ('final','void') and invoice_number is not null))
);
-- Explicit access policies. Client cannot update or delete finalized invoices.
alter table public.staff enable row level security;
alter table public.settings enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.invoice_counter enable row level security;
alter table public.invoices enable row level security;
create or replace function public.is_staff() returns boolean language sql stable security definer set search_path = '' as $$ select exists(select 1 from public.staff s where s.user_id=auth.uid()); $$;
revoke all on function public.is_staff() from public, anon;
grant execute on function public.is_staff() to authenticated;
create policy staff_own on public.staff for select to authenticated using(user_id=auth.uid());
create policy settings_read on public.settings for select to authenticated using(public.is_staff());
create policy settings_admin on public.settings for update to authenticated using(exists(select 1 from public.staff where user_id=auth.uid() and role='admin')) with check(exists(select 1 from public.staff where user_id=auth.uid() and role='admin'));
create policy customers_read on public.customers for select to authenticated using(public.is_staff());
create policy customers_insert on public.customers for insert to authenticated with check(public.is_staff());
create policy customers_update on public.customers for update to authenticated using(public.is_staff()) with check(public.is_staff());
create policy products_read on public.products for select to authenticated using(public.is_staff());
create policy products_insert on public.products for insert to authenticated with check(public.is_staff());
create policy products_update on public.products for update to authenticated using(public.is_staff()) with check(public.is_staff());
create policy invoices_read on public.invoices for select to authenticated using(public.is_staff());
create policy invoices_draft_insert on public.invoices for insert to authenticated with check(public.is_staff() and status='draft' and invoice_number is null and created_by=auth.uid());
create policy invoices_draft_update on public.invoices for update to authenticated using(public.is_staff() and status='draft') with check(public.is_staff() and status='draft' and invoice_number is null);
create policy invoices_draft_delete on public.invoices for delete to authenticated using(public.is_staff() and status='draft');
-- Finalize under row locks. Counter increments only on successful transaction.
create or replace function public.finalize_invoice(p_id uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v public.invoices%rowtype; n bigint; current_items jsonb; item jsonb; calc_sub numeric(12,2):=0; calc_total numeric(12,2); calc_qty numeric; calc_price numeric; calc_discount numeric;
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 select * into v from public.invoices where id=p_id for update;
 if not found then raise exception 'Invoice not found'; end if;
 if v.status <> 'draft' then raise exception 'Only drafts can be finalized'; end if;
 if coalesce(trim(v.customer_snapshot->>'name'),'')='' then raise exception 'Customer name required'; end if;
 if jsonb_typeof(v.items)<>'array' or jsonb_array_length(v.items)=0 then raise exception 'At least one item required'; end if;
 for item in select value from jsonb_array_elements(v.items) loop
  if coalesce(trim(item->>'name'),'')='' then raise exception 'Invalid product name'; end if;
  calc_qty:=(item->>'qty')::numeric; calc_price:=(item->>'price')::numeric;
  if calc_qty<=0 or calc_price<0 then raise exception 'Invalid quantity or price'; end if;
  calc_sub:=calc_sub + round(calc_qty*calc_price,2);
 end loop;
 if v.discount > calc_sub then raise exception 'Discount exceeds subtotal'; end if;
 calc_total:=round((calc_sub-v.discount)*(1+v.tax_rate/100),2);
 if v.paid > calc_total then raise exception 'Payment exceeds total'; end if;
 update public.invoice_counter set last_number=last_number+1 where id=1 returning last_number into n;
 update public.invoices set status='final',invoice_number=n,subtotal=calc_sub,total=calc_total,finalized_at=now(),
 issued_snapshot=jsonb_build_object('company', (select to_jsonb(s) from public.settings s where id=1), 'customer',v.customer_snapshot,'items',v.items,'issued_on',v.issued_on,'discount',v.discount,'tax_rate',v.tax_rate,'paid',v.paid,'notes',v.notes)
 where id=p_id;
 return n;
end $$;
create or replace function public.void_invoice(p_id uuid,p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if not exists(select 1 from public.staff where user_id=auth.uid() and role='admin') then raise exception 'Admin only'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Provide a reason (5+ characters)'; end if;
 update public.invoices set status='void',void_reason=p_reason,voided_at=now() where id=p_id and status='final';
 if not found then raise exception 'Only finalized invoices can be voided'; end if;
end $$;
revoke all on function public.finalize_invoice(uuid),public.void_invoice(uuid,text) from public,anon;
grant execute on function public.finalize_invoice(uuid),public.void_invoice(uuid,text) to authenticated;
-- Supabase defaults normally grant API access to public-schema resources;
-- keep these grants explicit for reproducibility.
grant select on public.staff,public.settings,public.customers,public.products,public.invoices to authenticated;
grant update on public.settings to authenticated;
grant insert,update on public.customers,public.products to authenticated;
grant insert,update,delete on public.invoices to authenticated;
revoke all on public.invoice_counter from anon,authenticated;
-- After adding first user in Authentication -> Users, run manually as project admin:
-- insert into public.staff(user_id,display_name,role) values('PASTE_AUTH_USER_UUID','Utshav','admin');
-- Keep staff sign-up disabled or invite users manually. Never publish service_role key.
