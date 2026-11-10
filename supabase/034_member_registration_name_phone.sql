-- Apply once after 033_connect_announcement_reads.sql.
begin;

-- This private function is called through the visitor-review and settings wrappers.
create or replace function public.complete_individual_registration_before_visitor_review()
returns text language plpgsql security definer set search_path = ''
as $$
declare
  person jsonb; account_email text; org_id uuid; branch uuid; given_name text; family_name text;
  birth_date date; person_type text; role_id uuid; matched_member uuid;
  review public.member_registration_reviews%rowtype; exact_matches uuid[]; possible_matches uuid[];
begin
  if auth.uid() is null then raise exception 'Sign in to complete registration.'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text, 0));
  if exists (select 1 from public.individual_registrations r where r.user_id = auth.uid()) then return 'completed'; end if;
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
      -- Serialize automatic links so a second registration cannot claim the same record.
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(org_id::text || ':member-registration', 0));
      select array_agg(m.id order by m.id) into exact_matches
      from public.members m
      where m.organization_id = org_id and m.branch_id is not distinct from branch and m.status = 'active'
        and lower(trim(m.first_name)) = lower(given_name) and lower(trim(m.last_name)) = lower(family_name)
        and exists (
          select 1 from unnest(array[public.registration_phone(m.phone), public.registration_phone(m.phone_2)]) stored(number)
          where stored.number is not null and stored.number ~ '[0-9]'
            and stored.number in (public.registration_phone(person ->> 'phone'), public.registration_phone(person ->> 'phone_2'))
        );
      if cardinality(exact_matches) = 1 then
        matched_member := exact_matches[1];
        perform 1 from public.members m where m.id = matched_member
          and m.organization_id = org_id and m.branch_id is not distinct from branch
          and m.status = 'active' and m.user_id is null
          and lower(trim(m.first_name)) = lower(given_name) and lower(trim(m.last_name)) = lower(family_name)
          and exists (
            select 1 from unnest(array[public.registration_phone(m.phone), public.registration_phone(m.phone_2)]) stored(number)
            where stored.number is not null and stored.number ~ '[0-9]'
              and stored.number in (public.registration_phone(person ->> 'phone'), public.registration_phone(person ->> 'phone_2'))
          )
          and not exists (select 1 from public.member_registration_reviews reserved
            where reserved.approved_member_id = m.id and reserved.status = 'approved')
          for update;
        if not found then matched_member := null; end if;
      end if;
      if matched_member is null then
        select array_agg(m.id order by m.id) into possible_matches from public.members m
        where m.organization_id = org_id and m.branch_id is not distinct from branch
          and m.user_id is null and m.status = 'active'
          and not exists (select 1 from public.member_registration_reviews reserved
            where reserved.approved_member_id = m.id and reserved.status = 'approved')
          and ((public.one_character_apart(lower(trim(m.first_name)), lower(given_name))
                and public.one_character_apart(lower(trim(m.last_name)), lower(family_name)))
            or exists (select 1 from unnest(array[public.registration_phone(m.phone), public.registration_phone(m.phone_2)]) stored(number)
              where stored.number is not null and stored.number ~ '[0-9]'
                and stored.number in (public.registration_phone(person ->> 'phone'), public.registration_phone(person ->> 'phone_2'))));
        insert into public.member_registration_reviews (user_id, organization_id, branch_id, registration, account_email)
          values (auth.uid(), org_id, branch, person, account_email);
        insert into public.member_registration_candidates (user_id, member_id)
          select auth.uid(), id from unnest(possible_matches) as ids(id);
        return 'pending';
      end if;
    end if;
    update public.members set user_id = auth.uid() where id = matched_member and organization_id = org_id
      and branch_id is not distinct from branch and status = 'active' and user_id is null;
    if not found then raise exception 'The member record is no longer available. Contact your church administrator.'; end if;
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
  insert into public.assignments (user_id, organization_id, branch_id, role_id) values (auth.uid(), org_id, branch, role_id);
  insert into public.profiles (user_id, first_name, last_name, phone, phone_2, date_of_birth, gender, marital_status, address, baptized)
    values (auth.uid(), given_name, family_name, trim(person ->> 'phone'), coalesce(trim(person ->> 'phone_2'), ''),
      birth_date, coalesce(person ->> 'gender', ''), coalesce(person ->> 'marital_status', ''),
      coalesce(trim(person ->> 'address'), ''), coalesce((person ->> 'baptized')::boolean, false))
    on conflict (user_id) do nothing;
  insert into public.individual_registrations (user_id, organization_id, person_type) values (auth.uid(), org_id, person_type);
  return 'completed';
end
$$;
revoke all on function public.complete_individual_registration_before_visitor_review() from public, anon, authenticated;

-- A pending or reviewed member request must use its saved snapshot, even if
-- the applicant subsequently changes their editable Auth metadata.
alter function public.complete_individual_registration_before_settings() rename to complete_registration_before_member_review_guard;
revoke all on function public.complete_registration_before_member_review_guard() from public, anon, authenticated;
create function public.complete_individual_registration_before_settings()
returns text language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Sign in to complete registration.'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text, 0));
  if exists (select 1 from public.member_registration_reviews r where r.user_id = auth.uid()) then
    return public.complete_individual_registration_before_visitor_review();
  end if;
  return public.complete_registration_before_member_review_guard();
end
$$;
revoke all on function public.complete_individual_registration_before_settings() from public, anon, authenticated;

create function public.search_member_registration_candidates(applicant_id uuid, search_text text)
returns table (member_id uuid, first_name text, last_name text, phone text, phone_2 text, email text, date_of_birth date)
language plpgsql stable security definer set search_path = ''
as $$
declare review public.member_registration_reviews%rowtype; term text;
begin
  select * into review from public.member_registration_reviews r where r.user_id = applicant_id and r.status = 'pending';
  if not found or not public.has_member_permission(review.organization_id, review.branch_id, 'update')
    or not public.has_member_permission(review.organization_id, review.branch_id, 'view') then
    raise exception 'Request unavailable or you do not have permission to search members.';
  end if;
  term := lower(trim(coalesce(search_text, '')));
  if length(term) < 2 or length(term) > 100 then raise exception 'Enter between 2 and 100 characters to search.'; end if;
  return query select m.id, m.first_name, m.last_name, m.phone, m.phone_2, m.email, m.date_of_birth
    from public.members m where m.organization_id = review.organization_id and m.branch_id is not distinct from review.branch_id
      and m.user_id is null and m.status = 'active'
      and not exists (select 1 from public.member_registration_reviews reserved where reserved.approved_member_id = m.id and reserved.status = 'approved')
      and (strpos(lower(m.first_name || ' ' || m.last_name), term) > 0
        or strpos(lower(coalesce(m.phone, '')), term) > 0 or strpos(lower(coalesce(m.phone_2, '')), term) > 0)
    order by m.first_name, m.last_name, m.id limit 30;
end
$$;

create or replace function public.review_member_registration(applicant_id uuid, target_member uuid, decision text)
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
    if not exists (select 1 from public.member_registration_candidates c where c.user_id = applicant_id and c.member_id = target_member)
      and not public.has_member_permission(review.organization_id, review.branch_id, 'view') then
      raise exception 'Member view permission is required to approve a different record.';
    end if;
    perform 1 from public.members m where m.id = target_member
      and m.organization_id = review.organization_id and m.branch_id is not distinct from review.branch_id
      and m.user_id is null and m.status = 'active' for update;
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
revoke all on function public.search_member_registration_candidates(uuid, text) from public, anon;
grant execute on function public.search_member_registration_candidates(uuid, text) to authenticated;
commit;
