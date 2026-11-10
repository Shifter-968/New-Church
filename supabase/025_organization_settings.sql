-- Apply once after 024_reported_absences.sql.
begin;

alter table public.organizations
  add column allow_member_registration boolean not null default true,
  add column allow_visitor_registration boolean not null default true;

create function public.organization_settings(target_org uuid)
returns table (name text, is_discoverable boolean, allow_member_registration boolean, allow_visitor_registration boolean)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_org_administrator(target_org) then raise exception 'Only an organization administrator or platform owner can manage church settings.'; end if;
  return query select o.name,o.is_discoverable,o.allow_member_registration,o.allow_visitor_registration
    from public.organizations o where o.id=target_org;
  if not found then raise exception 'Church not found.'; end if;
end
$$;

create function public.save_organization_settings(target_org uuid, church_name text, discoverable boolean,
  member_registration boolean, visitor_registration boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_org_administrator(target_org) then raise exception 'Only an organization administrator or platform owner can manage church settings.'; end if;
  if church_name is null or length(trim(church_name)) not between 2 and 120
    or discoverable is null or member_registration is null or visitor_registration is null then
    raise exception 'Provide a church name between 2 and 120 characters and valid registration settings.';
  end if;
  update public.organizations o set name=trim(church_name),is_discoverable=discoverable,
    allow_member_registration=member_registration,allow_visitor_registration=visitor_registration
    where o.id=target_org;
  if not found then raise exception 'Church not found.'; end if;
  insert into public.support_activity(organization_id,actor_id,resource_type,resource_id,action)
    values(target_org,auth.uid(),'organizations',target_org,'UPDATE');
end
$$;

-- Only expose settings for discoverable churches; enforce again at completion.
create function public.public_registration_options(target_org uuid)
returns table (allow_member_registration boolean, allow_visitor_registration boolean)
language sql stable security definer set search_path = ''
as $$
  select o.allow_member_registration,o.allow_visitor_registration from public.organizations o
    where o.id=target_org and o.is_discoverable
$$;

alter function public.complete_individual_registration() rename to complete_individual_registration_before_settings;
revoke all on function public.complete_individual_registration_before_settings() from public,anon,authenticated;
create function public.complete_individual_registration()
returns text language plpgsql security definer set search_path = ''
as $$
declare person jsonb; target_org uuid; person_type text; org public.organizations%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to complete registration.'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text,0));
  if exists(select 1 from public.individual_registrations r where r.user_id=auth.uid()) then return 'completed'; end if;
  select r.registration into person from public.member_registration_reviews r where r.user_id=auth.uid();
  if not found then
    select r.registration into person from public.visitor_registration_reviews r where r.user_id=auth.uid();
    if not found then
      select u.raw_user_meta_data -> 'individual_registration' into person
        from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
    end if;
  end if;
  if person is not null then
    target_org := nullif(person ->> 'organization_id','')::uuid;
    person_type := person ->> 'person_type';
    select * into org from public.organizations o where o.id=target_org for share;
    if not found or not org.is_discoverable then
      raise exception 'Church registration is unavailable. Contact your church administrator.';
    end if;
    if (person_type='MEMBER' and not org.allow_member_registration)
      or (person_type='VISITOR' and not org.allow_visitor_registration) then
      raise exception 'Registration for this account type is paused by your church. Contact your church administrator.';
    end if;
  end if;
  return public.complete_individual_registration_before_settings();
end
$$;

revoke all on function public.organization_settings(uuid),public.save_organization_settings(uuid,text,boolean,boolean,boolean),
  public.public_registration_options(uuid),public.complete_individual_registration() from public,anon;
grant execute on function public.organization_settings(uuid),public.save_organization_settings(uuid,text,boolean,boolean,boolean),
  public.complete_individual_registration() to authenticated;
grant execute on function public.public_registration_options(uuid) to anon,authenticated;
commit;
