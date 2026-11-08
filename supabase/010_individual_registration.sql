-- Apply once after 009_connect_conversations.sql.
begin;

alter table public.members add column date_of_birth date;
alter table public.members add column user_id uuid references auth.users(id) on delete set null;
alter table public.members add constraint members_user_organization_unique unique (organization_id, user_id);
revoke insert, update on public.members from public, anon, authenticated;
grant insert (organization_id, first_name, last_name, email, phone, branch_id, status, date_of_birth) on public.members to authenticated;
grant update (first_name, last_name, email, phone, branch_id, status, date_of_birth) on public.members to authenticated;

create function public.protect_linked_member_assignment()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.user_id is not null then
      raise exception 'Linked members cannot be deleted until account access management is available.';
    end if;
    return old;
  end if;
  if old.user_id is not null and (new.branch_id is distinct from old.branch_id or new.status is distinct from old.status) then
    raise exception 'A linked member branch or status cannot be changed until account access management is available.';
  end if;
  return new;
end
$$;
revoke all on function public.protect_linked_member_assignment() from public, anon, authenticated;
create trigger protect_linked_member_assignment before update or delete on public.members
  for each row execute function public.protect_linked_member_assignment();

create table public.visitors (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  user_id uuid references auth.users(id) on delete set null,
  first_name text not null check (length(trim(first_name)) between 1 and 100),
  last_name text not null check (length(trim(last_name)) between 1 and 100),
  email text not null check (length(trim(email)) between 3 and 320),
  phone text not null check (length(trim(phone)) between 1 and 40),
  created_at timestamptz not null default now(),
  foreign key (branch_id, organization_id) references public.branches(id, organization_id),
  unique (organization_id, user_id)
);
alter table public.visitors enable row level security;
revoke all on public.visitors from public, anon, authenticated;

create table public.individual_registrations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  person_type text not null check (person_type in ('MEMBER', 'VISITOR')),
  created_at timestamptz not null default now()
);
alter table public.individual_registrations enable row level security;
revoke all on public.individual_registrations from public, anon, authenticated;

create function public.individual_registration_ready()
returns boolean language sql stable security definer set search_path = ''
as $$ select true $$;
revoke all on function public.individual_registration_ready() from public;
grant execute on function public.individual_registration_ready() to anon, authenticated;

create function public.complete_individual_registration()
returns text language plpgsql security definer set search_path = ''
as $$
declare
  person jsonb; account_email text; org_id uuid; branch uuid; given_name text; family_name text;
  birth_date date; person_type text; role_id uuid; matched_member uuid; match_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in to complete registration.'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text, 0));
  if exists (select 1 from public.individual_registrations r where r.user_id = auth.uid()) then
    return 'completed';
  end if;
  select u.raw_user_meta_data -> 'individual_registration', u.email into person, account_email
    from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null;
  if not found then raise exception 'Confirm your email before completing registration.'; end if;
  if person is null then return 'none'; end if;
  org_id := nullif(person ->> 'organization_id', '')::uuid;
  branch := nullif(person ->> 'branch_id', '')::uuid;
  given_name := trim(person ->> 'first_name');
  family_name := trim(person ->> 'last_name');
  birth_date := (person ->> 'birth_date')::date;
  person_type := person ->> 'person_type';
  if person_type is null or person_type not in ('MEMBER', 'VISITOR')
    or given_name is null or length(given_name) not between 1 and 100
    or family_name is null or length(family_name) not between 1 and 100
    or birth_date is null or birth_date >= current_date
    or length(trim(coalesce(person ->> 'phone', ''))) not between 1 and 40
    or length(trim(coalesce(person ->> 'phone_2', ''))) > 40
    or length(trim(coalesce(person ->> 'address', ''))) > 255
    or coalesce(person ->> 'gender', '') not in ('', 'MALE', 'FEMALE', 'OTHER')
    or coalesce(person ->> 'marital_status', '') not in ('', 'SINGLE', 'MARRIED', 'ENGAGED', 'DIVORCED', 'UNOFFICIAL_RELATIONSHIP')
    or not exists (select 1 from public.organizations o where o.id = org_id and o.is_discoverable)
    or (branch is not null and not exists (select 1 from public.branches b where b.id = branch and b.organization_id = org_id))
    or (branch is null and exists (select 1 from public.branches b where b.organization_id = org_id)) then
    raise exception 'Registration details are invalid. Contact your church administrator.';
  end if;
  if person_type = 'MEMBER' then
    select count(*), (array_agg(m.id order by m.id))[1] into match_count, matched_member
      from public.members m where m.organization_id = org_id and m.branch_id is not distinct from branch
        and m.user_id is null and m.status = 'active'
        and lower(trim(m.first_name)) = lower(given_name)
        and lower(trim(m.last_name)) = lower(family_name)
        and lower(trim(m.email)) = lower(trim(account_email))
        and m.date_of_birth = birth_date;
    if match_count <> 1 then
      raise exception 'We could not verify your membership. Check your details or contact your church administrator.';
    end if;
    update public.members set user_id = auth.uid() where id = matched_member and user_id is null;
    if not found then raise exception 'We could not verify your membership. Check your details or contact your church administrator.'; end if;
  else
    insert into public.visitors (organization_id, branch_id, user_id, first_name, last_name, email, phone)
      values (org_id, branch, auth.uid(), given_name, family_name, account_email, trim(person ->> 'phone'));
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(org_id::text || ':individual-roles', 0));
  select r.id into role_id from public.roles r where r.organization_id = org_id and r.name = case person_type when 'MEMBER' then 'Member' else 'Visitor' end;
  if role_id is null then
    insert into public.roles (organization_id, name) values (org_id, case person_type when 'MEMBER' then 'Member' else 'Visitor' end) returning id into role_id;
  elsif exists (select 1 from public.roles r where r.id = role_id and (r.is_org_admin or cardinality(r.permissions) <> 0)) then
    raise exception 'The default individual role is not safe. Contact your church administrator.';
  end if;
  insert into public.assignments (user_id, organization_id, branch_id, role_id)
    values (auth.uid(), org_id, branch, role_id);
  insert into public.profiles (user_id, first_name, last_name, phone, phone_2, date_of_birth, gender, marital_status, address, baptized)
    values (auth.uid(), given_name, family_name, trim(person ->> 'phone'), coalesce(trim(person ->> 'phone_2'), ''),
      birth_date, coalesce(person ->> 'gender', ''), coalesce(person ->> 'marital_status', ''),
      coalesce(trim(person ->> 'address'), ''), coalesce((person ->> 'baptized')::boolean, false))
    on conflict (user_id) do nothing;
  insert into public.individual_registrations (user_id, organization_id, person_type) values (auth.uid(), org_id, person_type);
  return 'completed';
end
$$;
revoke all on function public.complete_individual_registration() from public, anon;
grant execute on function public.complete_individual_registration() to authenticated;
commit;
