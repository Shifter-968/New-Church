-- Apply once after 031_connect_announcement_workflow.sql on Supabase.
begin;

alter table public.organization_applications
  add column requested_plan_id uuid references public.plans(id),
  add column requested_plan_name text,
  add column requested_plan_price numeric(12,2),
  add column requested_plan_currency text,
  add column requested_plan_period text,
  add column payment_method text,
  add column transaction_reference text,
  add column payment_submitted_at timestamptz,
  add column receipt_submitted boolean not null default false;

create or replace function public.capture_organization_application()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare application jsonb; selected_plan public.plans%rowtype; method text; reference text;
begin
  application := new.raw_user_meta_data -> 'organization_application';
  if application is null then return new; end if;
  if application ->> 'purchase_authorized' is distinct from 'true' then raise exception 'Church registration requires authorization'; end if;
  select * into selected_plan from public.plans where id = (application ->> 'plan_id')::uuid and is_active;
  if not found then raise exception 'Select an available church plan.'; end if;
  if nullif(application ->> 'plan_price','')::numeric is distinct from selected_plan.price
    or application ->> 'plan_currency' is distinct from selected_plan.currency
    or application ->> 'plan_period' is distinct from selected_plan.billing_period then
    raise exception 'The selected plan price or billing period changed. Refresh and review it before registering.';
  end if;
  method := nullif(trim(application ->> 'payment_method'), '');
  reference := nullif(trim(application ->> 'transaction_reference'), '');
  if length(method) > 100 or length(reference) > 255
    or (selected_plan.price > 0 and (method is null or reference is null)) then
    raise exception 'Enter a payment method and transaction reference for the selected paid plan.';
  end if;
  insert into public.organization_applications
    (applicant_user_id, applicant_email, organization_name, account_role, address, city, country,
     first_name, last_name, phone, birth_date, gender, requested_plan_id, requested_plan_name,
     requested_plan_price, requested_plan_currency, requested_plan_period, payment_method, transaction_reference)
  values
    (new.id, new.email, trim(application ->> 'organization_name'), application ->> 'account_role',
     trim(application ->> 'address'), trim(application ->> 'city'), trim(application ->> 'country'),
     trim(application ->> 'first_name'), trim(application ->> 'last_name'), trim(application ->> 'phone'),
     (application ->> 'birth_date')::date, nullif(application ->> 'gender', ''), selected_plan.id,
     selected_plan.name, selected_plan.price, selected_plan.currency, selected_plan.billing_period, method, reference);
  return new;
end
$$;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('registration-payment-proofs', 'registration-payment-proofs', false, 8388608,
  array['application/pdf','image/jpeg','image/png']);

create function public.organization_payment_registration_ready()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists(select 1 from storage.buckets where id='registration-payment-proofs' and not public)
    and public.organization_registration_ready()
$$;
revoke all on function public.organization_payment_registration_ready() from public;
grant execute on function public.organization_payment_registration_ready() to anon, authenticated;

create function public.can_access_registration_receipt(object_name text, write_access boolean)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or write_access is null then return false; end if;
  if write_access then
    perform 1 from public.organization_applications a
    join auth.users u on u.id = a.applicant_user_id
    where a.applicant_user_id=auth.uid() and u.email_confirmed_at is not null
      and object_name=auth.uid()::text || '/receipt' and a.status='pending'
      and a.payment_submitted_at is null and a.requested_plan_id is not null
    for update of a;
    return found;
  end if;
  return exists (
    select 1 from public.organization_applications a
    join auth.users u on u.id = a.applicant_user_id
    where object_name = a.applicant_user_id::text || '/receipt'
      and (
        (a.applicant_user_id = auth.uid() and u.email_confirmed_at is not null)
        or (public.is_platform_owner() and a.receipt_submitted)
      )
  );
end
$$;
revoke all on function public.can_access_registration_receipt(text, boolean) from public, anon;
grant execute on function public.can_access_registration_receipt(text, boolean) to authenticated;

create policy "applicant uploads registration proof" on storage.objects for insert to authenticated
  with check (bucket_id = 'registration-payment-proofs' and public.can_access_registration_receipt(name, true));
create policy "applicant or owner downloads registration proof" on storage.objects for select to authenticated
  using (bucket_id = 'registration-payment-proofs' and public.can_access_registration_receipt(name, false));
create policy "applicant removes unfinished registration proof" on storage.objects for delete to authenticated
  using (bucket_id = 'registration-payment-proofs' and public.can_access_registration_receipt(name, true));

create function public.submit_organization_payment_details()
returns void language plpgsql security definer set search_path = ''
as $$
declare application public.organization_applications%rowtype;
begin
  select * into application from public.organization_applications
    where applicant_user_id = auth.uid() for update;
  if not found or application.status <> 'pending' or application.requested_plan_id is null
    or application.payment_submitted_at is not null then
    raise exception 'This application is not awaiting payment details.';
  end if;
  if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then
    raise exception 'Confirm your email before submitting payment details.';
  end if;
  update public.organization_applications set payment_submitted_at=now(),
    receipt_submitted=exists(select 1 from storage.objects where bucket_id='registration-payment-proofs'
      and name=auth.uid()::text || '/receipt')
    where id=application.id;
end
$$;
revoke all on function public.submit_organization_payment_details() from public, anon;
grant execute on function public.submit_organization_payment_details() to authenticated;

create or replace function public.review_organization_application(application_id uuid, decision text)
returns void language plpgsql security definer set search_path = ''
as $$
declare application public.organization_applications%rowtype; new_organization_id uuid; admin_role_id uuid;
begin
  if not public.is_platform_owner() then raise exception 'Only a platform owner can review applications'; end if;
  if decision is null or decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
  select * into application from public.organization_applications where id=application_id for update;
  if not found or application.status <> 'pending' then raise exception 'Application does not exist or has already been reviewed'; end if;
  if decision = 'approved' then
    if not exists(select 1 from auth.users where id=application.applicant_user_id and email_confirmed_at is not null) then
      raise exception 'The applicant must confirm their email before approval';
    end if;
    if application.requested_plan_id is not null and application.payment_submitted_at is null then
      raise exception 'The applicant must submit their payment details before approval.';
    end if;
    if application.requested_plan_id is not null and not exists
      (select 1 from public.plans where id=application.requested_plan_id and is_active) then
      raise exception 'The requested plan is no longer active. Resolve this before approval.';
    end if;
    insert into public.organizations(name) values(application.organization_name) returning id into new_organization_id;
    insert into public.roles(organization_id,name,is_org_admin)
      values(new_organization_id,'Organization Administrator',true) returning id into admin_role_id;
    insert into public.assignments(user_id,organization_id,role_id)
      values(application.applicant_user_id,new_organization_id,admin_role_id);
    if application.requested_plan_id is not null then
      insert into public.organization_plan_assignments(organization_id,plan_id,assigned_by)
        values(new_organization_id,application.requested_plan_id,auth.uid());
    end if;
  end if;
  update public.organization_applications set status=decision,reviewed_at=now(),reviewed_by=auth.uid(),
    organization_id=new_organization_id where id=application_id;
end
$$;
commit;
