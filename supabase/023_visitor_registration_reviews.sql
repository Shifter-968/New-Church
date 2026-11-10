-- Apply once after 022_users_and_access.sql.
begin;

create table public.visitor_registration_reviews (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  registration jsonb not null,
  account_email text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  approved_visitor_id uuid references public.visitors(id) on delete set null,
  create_new boolean not null default false,
  reviewed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  foreign key (branch_id, organization_id) references public.branches(id, organization_id)
);
create table public.visitor_registration_candidates (
  user_id uuid not null references public.visitor_registration_reviews(user_id) on delete cascade,
  visitor_id uuid not null references public.visitors(id) on delete cascade,
  primary key (user_id, visitor_id)
);
create unique index visitor_registration_approved_visitor_unique
  on public.visitor_registration_reviews (approved_visitor_id)
  where status = 'approved' and approved_visitor_id is not null;
alter table public.visitor_registration_reviews enable row level security;
alter table public.visitor_registration_candidates enable row level security;
revoke all on public.visitor_registration_reviews, public.visitor_registration_candidates from public, anon, authenticated;

create function public.list_visitor_registration_reviews(target_org uuid)
returns table (applicant_id uuid, applicant_email text, submitted jsonb, submitted_at timestamptz,
  visitor_id uuid, visitor_first_name text, visitor_last_name text, visitor_email text, visitor_phone text, branch_id uuid)
language sql stable security definer set search_path = ''
as $$
  select r.user_id, r.account_email, r.registration, r.created_at,
    v.id, v.first_name, v.last_name, v.email, v.phone, r.branch_id
  from public.visitor_registration_reviews r
  left join public.visitor_registration_candidates c on c.user_id = r.user_id
  left join public.visitors v on v.id = c.visitor_id and v.organization_id = r.organization_id
    and v.branch_id is not distinct from r.branch_id and v.user_id is null
    and not exists (select 1 from public.visitor_registration_reviews reserved
      where reserved.approved_visitor_id = v.id and reserved.status = 'approved')
  where r.organization_id = target_org and r.status = 'pending'
    and public.has_visitor_permission(r.organization_id, r.branch_id, 'update')
  order by r.created_at, r.user_id, v.id
$$;

create function public.review_visitor_registration(applicant_id uuid, target_visitor uuid, decision text)
returns void language plpgsql security definer set search_path = ''
as $$
declare review public.visitor_registration_reviews%rowtype;
begin
  if decision is null or decision not in ('approved', 'new', 'rejected') then raise exception 'Invalid decision.'; end if;
  select * into review from public.visitor_registration_reviews r where r.user_id = applicant_id for update;
  if not found or review.status <> 'pending'
    or not public.has_visitor_permission(review.organization_id, review.branch_id, 'update') then
    raise exception 'Request unavailable or you do not have permission to review it.';
  end if;
  if decision = 'approved' then
    perform 1 from public.visitors v join public.visitor_registration_candidates c on c.visitor_id = v.id
      where c.user_id = applicant_id and v.id = target_visitor
        and v.organization_id = review.organization_id and v.branch_id is not distinct from review.branch_id
        and v.user_id is null for update of v;
    if not found or exists (select 1 from public.visitor_registration_reviews r
      where r.approved_visitor_id = target_visitor and r.status = 'approved') then
      raise exception 'The selected visitor record is no longer available.';
    end if;
  end if;
  update public.visitor_registration_reviews set status = case when decision = 'new' then 'approved' else decision end,
    approved_visitor_id = case when decision = 'approved' then target_visitor else null end,
    create_new = decision = 'new',
    reviewed_by = auth.uid(), reviewed_at = now() where user_id = applicant_id;
end
$$;
revoke all on function public.list_visitor_registration_reviews(uuid), public.review_visitor_registration(uuid, uuid, text) from public, anon;
grant execute on function public.list_visitor_registration_reviews(uuid), public.review_visitor_registration(uuid, uuid, text) to authenticated;

alter function public.complete_individual_registration() rename to complete_individual_registration_before_visitor_review;
revoke all on function public.complete_individual_registration_before_visitor_review() from public, anon, authenticated;

create function public.complete_individual_registration()
returns text language plpgsql security definer set search_path = ''
as $$
declare
  person jsonb; account_email text; org_id uuid; branch uuid; given_name text; family_name text;
  birth_date date; role_id uuid; candidates uuid[]; review public.visitor_registration_reviews%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to complete registration.'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text, 0));
  if exists (select 1 from public.individual_registrations r where r.user_id = auth.uid()) then return 'completed'; end if;
  select * into review from public.visitor_registration_reviews r where r.user_id = auth.uid() for update;
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
  if person is null or person ->> 'person_type' is distinct from 'VISITOR' then
    return public.complete_individual_registration_before_visitor_review();
  end if;
  org_id := nullif(person ->> 'organization_id', '')::uuid;
  branch := nullif(person ->> 'branch_id', '')::uuid;
  given_name := trim(person ->> 'first_name');
  family_name := trim(person ->> 'last_name');
  birth_date := (person ->> 'birth_date')::date;
  if given_name is null or length(given_name) not between 1 and 100
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
  if review.status is distinct from 'approved' then
    select array_agg(v.id order by v.id) into candidates from public.visitors v
      where v.organization_id = org_id and v.branch_id is not distinct from branch
        and ((lower(trim(v.first_name)) = lower(given_name) and lower(trim(v.last_name)) = lower(family_name))
          or (nullif(trim(v.email), '') is not null and lower(trim(v.email)) = lower(trim(account_email)))
          or (public.registration_phone(v.phone) is not null and public.registration_phone(v.phone)
            in (public.registration_phone(person ->> 'phone'), public.registration_phone(person ->> 'phone_2'))));
    if candidates is null then return public.complete_individual_registration_before_visitor_review(); end if;
    insert into public.visitor_registration_reviews(user_id, organization_id, branch_id, registration, account_email)
      values(auth.uid(), org_id, branch, person, account_email);
    insert into public.visitor_registration_candidates(user_id, visitor_id)
      select auth.uid(), id from unnest(candidates) ids(id);
    return 'pending';
  end if;
  if review.create_new then
    insert into public.visitors (organization_id, branch_id, user_id, first_name, last_name, email, phone)
      values (org_id, branch, auth.uid(), given_name, family_name, account_email, trim(person ->> 'phone'));
  else
    update public.visitors set user_id = auth.uid() where id = review.approved_visitor_id
      and organization_id = org_id and branch_id is not distinct from branch and user_id is null;
    if not found then raise exception 'The visitor record is no longer available. Contact your church administrator.'; end if;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(org_id::text || ':individual-roles', 0));
  select r.id into role_id from public.roles r where r.organization_id = org_id and r.name = 'Visitor';
  if role_id is null then
    insert into public.roles (organization_id, name) values (org_id, 'Visitor') returning id into role_id;
  elsif exists (select 1 from public.roles r where r.id = role_id and (r.is_org_admin or cardinality(r.permissions) <> 0)) then
    raise exception 'The default individual role is not safe. Contact your church administrator.';
  end if;
  insert into public.assignments (user_id, organization_id, branch_id, role_id) values (auth.uid(), org_id, branch, role_id);
  insert into public.profiles (user_id, first_name, last_name, phone, phone_2, date_of_birth, gender, marital_status, address, baptized)
    values (auth.uid(), given_name, family_name, trim(person ->> 'phone'), coalesce(trim(person ->> 'phone_2'), ''),
      birth_date, coalesce(person ->> 'gender', ''), coalesce(person ->> 'marital_status', ''),
      coalesce(trim(person ->> 'address'), ''), coalesce((person ->> 'baptized')::boolean, false))
    on conflict (user_id) do nothing;
  insert into public.individual_registrations (user_id, organization_id, person_type) values (auth.uid(), org_id, 'VISITOR');
  return 'completed';
end
$$;
revoke all on function public.complete_individual_registration() from public, anon;
grant execute on function public.complete_individual_registration() to authenticated;
commit;
