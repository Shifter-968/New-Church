-- Apply once after 035_google_organization_registration.sql.
begin;

alter table public.members
  add column gender text,
  add column marital_status text,
  add column residence text,
  add column baptized boolean;

grant insert (organization_id, first_name, last_name, email, phone, phone_2, branch_id, status,
  date_of_birth, gender, marital_status, residence, baptized) on public.members to authenticated;
grant update (first_name, last_name, email, phone, phone_2, branch_id, status,
  date_of_birth, gender, marital_status, residence, baptized) on public.members to authenticated;

create function public.validate_member_profile_fields()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.marital_status := coalesce(nullif(trim(new.marital_status), ''), 'SINGLE');
  end if;
  if tg_op = 'INSERT'
    or new.first_name is distinct from old.first_name
    or new.last_name is distinct from old.last_name
    or new.gender is distinct from old.gender
    or new.date_of_birth is distinct from old.date_of_birth
    or new.marital_status is distinct from old.marital_status then
    if length(trim(coalesce(new.first_name, ''))) not between 1 and 100
      or length(trim(coalesce(new.last_name, ''))) not between 1 and 100
      or coalesce(new.gender, '') not in ('MALE', 'FEMALE', 'OTHER')
      or new.date_of_birth is null or new.date_of_birth >= current_date
      or coalesce(new.marital_status, '') not in ('SINGLE', 'COURTSHIP', 'ENGAGED', 'MARRIED', 'DIVORCED', 'WIDOWED') then
      raise exception 'First name, last name, gender, date of birth and a valid marital status are required.';
    end if;
  end if;
  if new.residence is not null and length(new.residence) > 255 then
    raise exception 'Residence cannot exceed 255 characters.';
  end if;
  return new;
end
$$;
revoke all on function public.validate_member_profile_fields() from public, anon, authenticated;
create trigger validate_member_profile_fields before insert or update on public.members
  for each row execute function public.validate_member_profile_fields();

create function public.sync_linked_person_email()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare account_email text;
begin
  if new.user_id is not null then
    select u.email into account_email from auth.users u where u.id = new.user_id;
    if account_email is not null then
      new.email := account_email;
    elsif tg_table_name = 'visitors' then
      raise exception 'A linked visitor account must have an email address.';
    end if;
  end if;
  return new;
end
$$;
revoke all on function public.sync_linked_person_email() from public, anon, authenticated;
create trigger sync_linked_member_email before insert or update on public.members
  for each row execute function public.sync_linked_person_email();
create trigger sync_linked_visitor_email before insert or update on public.visitors
  for each row execute function public.sync_linked_person_email();

alter table public.church_teams add column criteria jsonb;
alter table public.church_team_members add column auto_assigned boolean not null default false;
grant update (name, criteria) on public.church_teams to authenticated;
revoke insert on public.church_team_members from authenticated;
grant insert (organization_id, team_id, member_id, visitor_id) on public.church_team_members to authenticated;

create function public.validate_ministry_criteria()
returns trigger language plpgsql set search_path = ''
as $$
declare item text; minimum_age integer; maximum_age integer; key_name text;
begin
  if new.kind = 'department' and new.criteria is not null then
    raise exception 'Departments use manual membership; criteria are only available for ministries.';
  end if;
  if new.criteria is null then return new; end if;
  if jsonb_typeof(new.criteria) is distinct from 'object' then
    raise exception 'Ministry criteria must be an object.';
  end if;
  for key_name in select jsonb_object_keys(new.criteria) loop
    if key_name not in ('gender', 'marital_status', 'min_age', 'max_age', 'baptized', 'residence') then
      raise exception 'Unsupported ministry criterion: %.', key_name;
    end if;
  end loop;
  if new.criteria ? 'gender' then
    if jsonb_typeof(new.criteria -> 'gender') <> 'array' then raise exception 'Gender criteria must be a list.'; end if;
    for item in select jsonb_array_elements_text(new.criteria -> 'gender') loop
      if item is null or item not in ('MALE', 'FEMALE', 'OTHER') then raise exception 'Choose a valid gender criterion.'; end if;
    end loop;
  end if;
  if new.criteria ? 'marital_status' then
    if jsonb_typeof(new.criteria -> 'marital_status') <> 'array' then raise exception 'Marital status criteria must be a list.'; end if;
    for item in select jsonb_array_elements_text(new.criteria -> 'marital_status') loop
      if item is null or item not in ('SINGLE', 'COURTSHIP', 'ENGAGED', 'MARRIED', 'DIVORCED', 'WIDOWED') then raise exception 'Choose a valid marital status criterion.'; end if;
    end loop;
  end if;
  if new.criteria ? 'min_age' then
    if jsonb_typeof(new.criteria -> 'min_age') <> 'number' then raise exception 'Minimum age must be a whole number.'; end if;
    if (new.criteria ->> 'min_age')::numeric <> trunc((new.criteria ->> 'min_age')::numeric) then
      raise exception 'Minimum age must be a whole number.';
    end if;
    minimum_age := (new.criteria ->> 'min_age')::integer;
    if minimum_age not between 0 and 130 then raise exception 'Minimum age must be from 0 to 130.'; end if;
  end if;
  if new.criteria ? 'max_age' then
    if jsonb_typeof(new.criteria -> 'max_age') <> 'number' then raise exception 'Maximum age must be a whole number.'; end if;
    if (new.criteria ->> 'max_age')::numeric <> trunc((new.criteria ->> 'max_age')::numeric) then
      raise exception 'Maximum age must be a whole number.';
    end if;
    maximum_age := (new.criteria ->> 'max_age')::integer;
    if maximum_age not between 0 and 130 then raise exception 'Maximum age must be from 0 to 130.'; end if;
  end if;
  if minimum_age is not null and maximum_age is not null and minimum_age > maximum_age then
    raise exception 'Minimum age cannot exceed maximum age.';
  end if;
  if new.criteria ? 'baptized' and jsonb_typeof(new.criteria -> 'baptized') <> 'boolean' then
    raise exception 'Baptism criterion must be yes or no.';
  end if;
  if new.criteria ? 'residence' and
    (jsonb_typeof(new.criteria -> 'residence') <> 'string'
      or length(trim(new.criteria ->> 'residence')) not between 1 and 100) then
    raise exception 'Residence criterion must be between 1 and 100 characters.';
  end if;
  return new;
end
$$;
revoke all on function public.validate_ministry_criteria() from public, anon, authenticated;
create trigger validate_ministry_criteria before insert or update of kind, criteria on public.church_teams
  for each row execute function public.validate_ministry_criteria();

create function public.member_matches_ministry_criteria(
  target_criteria jsonb, target_gender text, target_birth_date date, target_marital_status text,
  target_baptized boolean, target_residence text, target_status text
)
returns boolean language sql stable set search_path = ''
as $$
  select target_criteria is not null
    and (not (target_criteria ? 'gender') or jsonb_array_length(target_criteria -> 'gender') = 0
      or coalesce(target_criteria -> 'gender' ? target_gender, false))
    and (not (target_criteria ? 'marital_status') or jsonb_array_length(target_criteria -> 'marital_status') = 0
      or coalesce(target_criteria -> 'marital_status' ? target_marital_status, false))
    and (not (target_criteria ? 'min_age') or (target_birth_date is not null
      and date_part('year', age(current_date, target_birth_date)) >= (target_criteria ->> 'min_age')::integer))
    and (not (target_criteria ? 'max_age') or (target_birth_date is not null
      and date_part('year', age(current_date, target_birth_date)) <= (target_criteria ->> 'max_age')::integer))
    and (not (target_criteria ? 'baptized') or coalesce(target_baptized = (target_criteria ->> 'baptized')::boolean, false))
    and (not (target_criteria ? 'residence') or
      strpos(lower(coalesce(target_residence, '')), lower(target_criteria ->> 'residence')) > 0)
    and target_status = 'active'
$$;
revoke all on function public.member_matches_ministry_criteria(jsonb, text, date, text, boolean, text, text) from public, anon;

create function public.sync_member_ministry_assignments()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.church_team_members tm
  using public.church_teams t
  where tm.team_id = t.id and tm.member_id = new.id and tm.auto_assigned
    and (t.criteria is null or not public.member_matches_ministry_criteria(
      t.criteria, new.gender, new.date_of_birth, new.marital_status, new.baptized, new.residence, new.status));

  insert into public.church_team_members (organization_id, team_id, member_id, auto_assigned)
  select new.organization_id, t.id, new.id, true
  from public.church_teams t
  where t.organization_id = new.organization_id and t.kind = 'ministry' and t.criteria is not null
    and public.member_matches_ministry_criteria(
      t.criteria, new.gender, new.date_of_birth, new.marital_status, new.baptized, new.residence, new.status)
  on conflict (team_id, member_id) do nothing;
  return new;
end
$$;
revoke all on function public.sync_member_ministry_assignments() from public, anon, authenticated;
create trigger sync_member_ministry_assignments after insert or update of gender, date_of_birth, marital_status,
  baptized, residence, status on public.members
  for each row execute function public.sync_member_ministry_assignments();

create function public.sync_ministry_criteria_assignments()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.church_team_members tm
  where tm.team_id = new.id and tm.auto_assigned and (
    new.criteria is null or not exists (
      select 1 from public.members m where m.id = tm.member_id and m.organization_id = new.organization_id
        and public.member_matches_ministry_criteria(
          new.criteria, m.gender, m.date_of_birth, m.marital_status, m.baptized, m.residence, m.status)
    )
  );
  if new.kind = 'ministry' and new.criteria is not null then
    insert into public.church_team_members (organization_id, team_id, member_id, auto_assigned)
    select m.organization_id, new.id, m.id, true
    from public.members m where m.organization_id = new.organization_id
      and public.member_matches_ministry_criteria(
        new.criteria, m.gender, m.date_of_birth, m.marital_status, m.baptized, m.residence, m.status)
    on conflict (team_id, member_id) do nothing;
  end if;
  return new;
end
$$;
revoke all on function public.sync_ministry_criteria_assignments() from public, anon, authenticated;
create trigger sync_ministry_criteria_assignments after insert or update of kind, criteria on public.church_teams
  for each row execute function public.sync_ministry_criteria_assignments();

create function public.protect_automatic_ministry_membership()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.auto_assigned and pg_catalog.pg_trigger_depth() = 1 and exists (
    select 1 from public.church_teams t
    join public.members m on m.id = old.member_id and m.organization_id = old.organization_id
    where t.id = old.team_id and t.criteria is not null
      and public.member_matches_ministry_criteria(
        t.criteria, m.gender, m.date_of_birth, m.marital_status, m.baptized, m.residence, m.status)
  ) then
    raise exception 'This member still matches the ministry criteria. Update the profile or criteria to remove the automatic assignment.';
  end if;
  return old;
end
$$;
revoke all on function public.protect_automatic_ministry_membership() from public, anon, authenticated;
create trigger protect_automatic_ministry_membership before delete on public.church_team_members
  for each row execute function public.protect_automatic_ministry_membership();

commit;
