-- Apply once after 009_connect_conversations.sql.
begin;

alter table public.members add column date_of_birth date;
alter table public.members add column phone_2 text check (length(phone_2) <= 40);
alter table public.members add column user_id uuid references auth.users(id) on delete set null;
alter table public.members add constraint members_user_organization_unique unique (organization_id, user_id);
revoke insert, update on public.members from public, anon, authenticated;
grant insert (organization_id, first_name, last_name, email, phone, phone_2, branch_id, status, date_of_birth) on public.members to authenticated;
grant update (first_name, last_name, email, phone, phone_2, branch_id, status, date_of_birth) on public.members to authenticated;

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

create table public.member_registration_reviews (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  registration jsonb not null,
  account_email text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  approved_member_id uuid references public.members(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  foreign key (branch_id, organization_id) references public.branches(id, organization_id)
);
create table public.member_registration_candidates (
  user_id uuid not null references public.member_registration_reviews(user_id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  primary key (user_id, member_id)
);
create unique index member_registration_approved_member_unique on public.member_registration_reviews (approved_member_id)
  where status = 'approved' and approved_member_id is not null;
alter table public.member_registration_reviews enable row level security;
alter table public.member_registration_candidates enable row level security;
revoke all on public.member_registration_reviews, public.member_registration_candidates from public, anon, authenticated;

-- A single insertion, deletion or substitution is a possible typo, not proof of identity.
create function public.one_character_apart(a text, b text)
returns boolean language plpgsql immutable strict set search_path = ''
as $$
declare i integer := 1; j integer := 1; edits integer := 0;
begin
  if abs(length(a) - length(b)) > 1 then return false; end if;
  while i <= length(a) and j <= length(b) loop
    if substr(a, i, 1) = substr(b, j, 1) then i := i + 1; j := j + 1;
    else
      edits := edits + 1;
      if edits > 1 then return false; end if;
      if length(a) >= length(b) then i := i + 1; end if;
      if length(b) >= length(a) then j := j + 1; end if;
    end if;
  end loop;
  return edits + (length(a) - i + 1) + (length(b) - j + 1) <= 1;
end
$$;
revoke all on function public.one_character_apart(text, text) from public, anon, authenticated;

create function public.registration_phone(value text)
returns text language sql immutable set search_path = ''
as $$
  select case when nullif(trim(value), '') is null then null
    when regexp_replace(value, '[^0-9]', '', 'g') <> '' then regexp_replace(value, '[^0-9]', '', 'g')
    else lower(trim(value)) end
$$;
revoke all on function public.registration_phone(text) from public, anon, authenticated;

create function public.list_member_registration_reviews(target_org uuid)
returns table (applicant_id uuid, applicant_email text, submitted jsonb, submitted_at timestamptz,
  member_id uuid, member_first_name text, member_last_name text, member_email text,
  member_phone text, member_phone_2 text, member_birth_date date, branch_id uuid)
language sql stable security definer set search_path = ''
as $$
  select r.user_id, r.account_email, r.registration, r.created_at, m.id, m.first_name, m.last_name,
    m.email, m.phone, m.phone_2, m.date_of_birth, r.branch_id
  from public.member_registration_reviews r
  left join public.member_registration_candidates c on c.user_id = r.user_id
  left join public.members m on m.id = c.member_id
    and m.organization_id = r.organization_id and m.branch_id is not distinct from r.branch_id
    and m.user_id is null and m.status = 'active'
  where r.organization_id = target_org and r.status = 'pending'
    and public.has_member_permission(r.organization_id, r.branch_id, 'update')
  order by r.created_at, r.user_id, m.id
$$;

create function public.review_member_registration(applicant_id uuid, target_member uuid, decision text)
returns void language plpgsql security definer set search_path = ''
as $$
declare review public.member_registration_reviews%rowtype;
begin
  if decision is null or decision not in ('approved', 'rejected') then raise exception 'Invalid decision.'; end if;
  select * into review from public.member_registration_reviews r where r.user_id = applicant_id for update;
  if not found or review.status <> 'pending'
    or not public.has_member_permission(review.organization_id, review.branch_id, 'update') then
    raise exception 'Request unavailable or you do not have permission to review it.';
  end if;
  if decision = 'approved' then
    perform 1 from public.members m join public.member_registration_candidates c on c.member_id = m.id
      where c.user_id = applicant_id and m.id = target_member
        and m.organization_id = review.organization_id and m.branch_id is not distinct from review.branch_id
        and m.user_id is null and m.status = 'active' for update of m;
    if not found then raise exception 'The selected member record is no longer available.'; end if;
    if exists (select 1 from public.member_registration_reviews r where r.approved_member_id = target_member and r.status = 'approved') then
      raise exception 'The selected member record is already reserved for another registration.';
    end if;
  end if;
  update public.member_registration_reviews set status = decision,
    approved_member_id = case when decision = 'approved' then target_member else null end,
    reviewed_by = auth.uid(), reviewed_at = now() where user_id = applicant_id;
end
$$;
revoke all on function public.list_member_registration_reviews(uuid), public.review_member_registration(uuid, uuid, text) from public, anon;
grant execute on function public.list_member_registration_reviews(uuid), public.review_member_registration(uuid, uuid, text) to authenticated;

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
  review public.member_registration_reviews%rowtype; exact_matches uuid[]; possible_matches uuid[];
begin
  if auth.uid() is null then raise exception 'Sign in to complete registration.'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text, 0));
  if exists (select 1 from public.individual_registrations r where r.user_id = auth.uid()) then
    return 'completed';
  end if;
  select * into review from public.member_registration_reviews r where r.user_id = auth.uid() for update;
  if found and review.status = 'pending' then return 'pending'; end if;
  if found and review.status = 'rejected' then return 'rejected'; end if;
  select u.raw_user_meta_data -> 'individual_registration', u.email into person, account_email
    from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null;
  if not found then raise exception 'Confirm your email before completing registration.'; end if;
  if review.status = 'approved' then
    if lower(trim(account_email)) <> lower(trim(review.account_email)) then
      raise exception 'Your account email changed after review. Contact your church administrator.';
    end if;
    person := review.registration;
  end if;
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
    if review.status = 'approved' then
      matched_member := review.approved_member_id;
    else
      with candidates as (select m.id,
        (lower(trim(m.first_name)) <> lower(given_name))::integer +
        (lower(trim(m.last_name)) <> lower(family_name))::integer +
        (nullif(trim(m.email), '') is not null and lower(trim(m.email)) <> lower(trim(account_email)))::integer +
        (m.date_of_birth is not null and m.date_of_birth <> birth_date)::integer +
        (coalesce(public.registration_phone(m.phone), public.registration_phone(m.phone_2)) is not null
          and not exists (select 1 from unnest(array[public.registration_phone(m.phone), public.registration_phone(m.phone_2)]) stored(number)
            where stored.number is not null and stored.number in (public.registration_phone(person ->> 'phone'), public.registration_phone(person ->> 'phone_2'))))::integer as differences
      from public.members m where m.organization_id = org_id and m.branch_id is not distinct from branch
        and m.user_id is null and m.status = 'active'
        and not exists (select 1 from public.member_registration_reviews reserved where reserved.approved_member_id = m.id and reserved.status = 'approved')
        and public.one_character_apart(lower(trim(m.first_name)), lower(given_name))
        and public.one_character_apart(lower(trim(m.last_name)), lower(family_name)))
      select array_agg(id order by id) filter (where differences = 0),
        array_agg(id order by id) filter (where differences <= 1)
        into exact_matches, possible_matches from candidates;
      match_count := coalesce(cardinality(exact_matches), 0);
      matched_member := exact_matches[1];
      if match_count <> 1 then
        if coalesce(cardinality(possible_matches), 0) = 0 then raise exception 'We could not verify your membership. Check your details or contact your church administrator.'; end if;
        insert into public.member_registration_reviews (user_id, organization_id, branch_id, registration, account_email)
          values (auth.uid(), org_id, branch, person, account_email);
        insert into public.member_registration_candidates (user_id, member_id)
          select auth.uid(), id from unnest(possible_matches) as ids(id);
        return 'pending';
      end if;
    end if;
    perform 1 from public.members m where m.id = matched_member for update;
    if review.status is distinct from 'approved' and exists
      (select 1 from public.member_registration_reviews r where r.approved_member_id = matched_member and r.status = 'approved') then
      raise exception 'We could not verify your membership. Check your details or contact your church administrator.';
    end if;
    update public.members set user_id = auth.uid() where id = matched_member and organization_id = org_id
      and branch_id is not distinct from branch and status = 'active' and user_id is null;
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
