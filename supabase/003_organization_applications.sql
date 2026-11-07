-- Apply once after 002_public_search_and_branch_admin.sql.
-- Organization applications are linked to an Auth account; approval is owner-only.
begin;

create table public.organization_applications (
  id uuid primary key default gen_random_uuid(),
  applicant_user_id uuid not null references auth.users(id) on delete cascade,
  applicant_email text not null,
  organization_name text not null check (length(trim(organization_name)) between 2 and 120),
  account_role text not null check (account_role in ('FOUNDING_PASTOR', 'CHURCH_ADMIN')),
  address text not null check (length(trim(address)) between 1 and 255),
  city text not null check (length(trim(city)) between 1 and 120),
  country text not null check (length(trim(country)) between 1 and 120),
  first_name text not null check (length(trim(first_name)) between 1 and 100),
  last_name text not null check (length(trim(last_name)) between 1 and 100),
  phone text not null check (length(trim(phone)) between 1 and 40),
  birth_date date not null check (birth_date < current_date),
  gender text check (gender is null or gender in ('MALE', 'FEMALE', 'OTHER')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  organization_id uuid references public.organizations(id),
  unique (applicant_user_id)
);

alter table public.organization_applications enable row level security;
create policy "owner or applicant can view applications" on public.organization_applications
  for select to authenticated using (public.is_platform_owner() or applicant_user_id = auth.uid());
grant select on public.organization_applications to authenticated;

create function public.capture_organization_application()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare application jsonb;
begin
  application := new.raw_user_meta_data -> 'organization_application';
  if application is null then return new; end if;
  if application ->> 'purchase_authorized' is distinct from 'true' then
    raise exception 'Church registration requires authorization';
  end if;
  insert into public.organization_applications
    (applicant_user_id, applicant_email, organization_name, account_role, address, city, country,
     first_name, last_name, phone, birth_date, gender)
  values
    (new.id, new.email, trim(application ->> 'organization_name'), application ->> 'account_role',
     trim(application ->> 'address'), trim(application ->> 'city'), trim(application ->> 'country'),
     trim(application ->> 'first_name'), trim(application ->> 'last_name'),
     trim(application ->> 'phone'), (application ->> 'birth_date')::date,
     nullif(application ->> 'gender', ''));
  return new;
end
$$;
revoke all on function public.capture_organization_application() from public, anon, authenticated;
create trigger capture_organization_application after insert on auth.users
  for each row execute function public.capture_organization_application();

create function public.organization_registration_ready()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from pg_catalog.pg_trigger
    where tgname = 'capture_organization_application'
      and tgrelid = 'auth.users'::regclass and tgenabled <> 'D' and not tgisinternal)
$$;
revoke all on function public.organization_registration_ready() from public;
grant execute on function public.organization_registration_ready() to anon, authenticated;

create function public.review_organization_application(application_id uuid, decision text)
returns void language plpgsql security definer set search_path = ''
as $$
declare application public.organization_applications%rowtype;
declare new_organization_id uuid;
declare admin_role_id uuid;
begin
  if not public.is_platform_owner() then
    raise exception 'Only a platform owner can review applications';
  end if;
  if decision not in ('approved', 'rejected') or decision is null then
    raise exception 'Invalid decision';
  end if;
  select * into application from public.organization_applications where id = application_id for update;
  if not found or application.status <> 'pending' then
    raise exception 'Application does not exist or has already been reviewed';
  end if;
  if decision = 'approved' then
    if not exists (select 1 from auth.users where id = application.applicant_user_id and email_confirmed_at is not null) then
      raise exception 'The applicant must confirm their email before approval';
    end if;
    insert into public.organizations (name) values (application.organization_name) returning id into new_organization_id;
    insert into public.roles (organization_id, name, is_org_admin)
      values (new_organization_id, 'Organization Administrator', true) returning id into admin_role_id;
    insert into public.assignments (user_id, organization_id, role_id)
      values (application.applicant_user_id, new_organization_id, admin_role_id);
  end if;
  update public.organization_applications set status = decision, reviewed_at = now(),
    reviewed_by = auth.uid(), organization_id = new_organization_id where id = application_id;
end
$$;
revoke all on function public.review_organization_application(uuid, text) from public, anon;
grant execute on function public.review_organization_application(uuid, text) to authenticated;
commit;
