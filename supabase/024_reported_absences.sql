-- Apply once after 023_visitor_registration_reviews.sql.
begin;

create table public.reported_absences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  event_id uuid not null references public.church_events(id) on delete restrict,
  branch_id uuid not null,
  member_id uuid references public.members(id) on delete restrict,
  visitor_id uuid references public.visitors(id) on delete restrict,
  reported_by uuid not null references auth.users(id),
  reason text not null default '' check (length(reason) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((member_id is null) <> (visitor_id is null)),
  foreign key (branch_id, organization_id) references public.branches(id, organization_id),
  unique (event_id, member_id),
  unique (event_id, visitor_id)
);
create index reported_absences_org_idx on public.reported_absences (organization_id, updated_at desc, id);
alter table public.reported_absences enable row level security;
revoke all on public.reported_absences from public, anon, authenticated;
create trigger reported_absence_activity after insert or update or delete on public.reported_absences
  for each row execute function public.record_support_activity();

-- A report is a notice, not an attendance record; a later check-in remains authoritative.
create function public.my_absence_events(target_org uuid)
returns table (event_id uuid, title text, starts_at timestamptz, ends_at timestamptz,
  branch_name text, reason text, reported boolean, present boolean)
language sql stable security definer set search_path = ''
as $$
  with person as (
    select id, branch_id, 'member'::text as kind from public.members
      where organization_id = target_org and user_id = auth.uid() and status = 'active'
    union all
    select id, branch_id, 'visitor'::text from public.visitors
      where organization_id = target_org and user_id = auth.uid()
  )
  select e.id, e.title, e.starts_at, e.ends_at, b.name, coalesce(r.reason,''), r.id is not null,
    exists(select 1 from public.event_attendance a where a.event_id=e.id and
      ((p.kind='member' and a.member_id=p.id) or (p.kind='visitor' and a.visitor_id=p.id)))
  from person p
  join public.branches b on b.id=p.branch_id and b.organization_id=target_org
  join public.church_events e on e.organization_id=target_org
  left join public.reported_absences r on r.event_id=e.id and r.organization_id=target_org and
    ((p.kind='member' and r.member_id=p.id) or (p.kind='visitor' and r.visitor_id=p.id))
  where (select count(*) from person)=1
    and (e.ends_at >= now() or r.id is not null)
    and exists(select 1 from public.assignments a where a.user_id=auth.uid() and a.active
      and a.organization_id=target_org and (a.branch_id is null or a.branch_id=p.branch_id))
    and public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams)
  order by (e.ends_at < now()), case when e.ends_at >= now() then e.starts_at end,
    case when e.ends_at < now() then e.starts_at end desc,e.id limit 100
$$;

create function public.report_my_absence(target_event uuid, report_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare ev public.church_events%rowtype; person record; person_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in to report an absence.'; end if;
  if report_reason is null or length(trim(report_reason)) > 500 then raise exception 'Reason must be at most 500 characters.'; end if;
  select * into ev from public.church_events where id=target_event;
  if not found or ev.ends_at < now()
    or not public.audience_visible(ev.organization_id,ev.audience_everyone,ev.audience_roles,ev.audience_teams) then
    raise exception 'This event is unavailable for reporting.';
  end if;
  select count(*) into person_count from (
    select id from public.members where organization_id=ev.organization_id and user_id=auth.uid() and status='active'
    union all select id from public.visitors where organization_id=ev.organization_id and user_id=auth.uid()
  ) p;
  if person_count <> 1 then raise exception 'An unambiguous linked member or visitor record is required.'; end if;
  select * into person from (
    select id,branch_id,'member'::text as kind from public.members where organization_id=ev.organization_id and user_id=auth.uid() and status='active'
    union all select id,branch_id,'visitor'::text from public.visitors where organization_id=ev.organization_id and user_id=auth.uid()
  ) p;
  if person.branch_id is null or not exists(select 1 from public.assignments a where a.user_id=auth.uid() and a.active
    and a.organization_id=ev.organization_id and (a.branch_id is null or a.branch_id=person.branch_id)) then
    raise exception 'An active assignment for your branch is required.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(target_event::text || person.id::text,0));
  if exists(select 1 from public.event_attendance a where a.event_id=target_event
    and ((person.kind='member' and a.member_id=person.id) or (person.kind='visitor' and a.visitor_id=person.id))) then
    raise exception 'You are already marked present for this event.';
  end if;
  update public.reported_absences r set reason=trim(report_reason),updated_at=now()
    where r.event_id=target_event and r.reported_by=auth.uid()
      and ((person.kind='member' and r.member_id=person.id) or (person.kind='visitor' and r.visitor_id=person.id));
  if not found then
    insert into public.reported_absences(organization_id,event_id,branch_id,member_id,visitor_id,reported_by,reason)
    values(ev.organization_id,target_event,person.branch_id,
      case when person.kind='member' then person.id end,
      case when person.kind='visitor' then person.id end,auth.uid(),trim(report_reason));
  end if;
end
$$;

create function public.withdraw_my_absence(target_event uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.reported_absences r using public.church_events e
    where r.event_id=target_event and e.id=r.event_id and r.reported_by=auth.uid()
      and public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams)
      and exists(select 1 from public.assignments a where a.user_id=auth.uid() and a.active
        and a.organization_id=r.organization_id and (a.branch_id is null or a.branch_id=r.branch_id));
  if not found then raise exception 'Absence notice unavailable.'; end if;
end
$$;

create function public.list_reported_absences(target_org uuid)
returns table (id uuid, event_id uuid, title text, starts_at timestamptz, branch_id uuid, branch_name text,
  person_name text, person_kind text, phone text, reason text, updated_at timestamptz, present boolean)
language sql stable security definer set search_path = ''
as $$
  select r.id,e.id,e.title,e.starts_at,r.branch_id,b.name,
    coalesce(m.first_name,v.first_name) || ' ' || coalesce(m.last_name,v.last_name),
    case when r.member_id is not null then 'member' else 'visitor' end,
    coalesce(m.phone,v.phone),r.reason,r.updated_at,
    exists(select 1 from public.event_attendance a where a.event_id=r.event_id
      and ((r.member_id is not null and a.member_id=r.member_id) or (r.visitor_id is not null and a.visitor_id=r.visitor_id)))
  from public.reported_absences r
  join public.church_events e on e.id=r.event_id and e.organization_id=r.organization_id
  join public.branches b on b.id=r.branch_id and b.organization_id=r.organization_id
  left join public.members m on m.id=r.member_id and m.organization_id=r.organization_id
  left join public.visitors v on v.id=r.visitor_id and v.organization_id=r.organization_id
  where r.organization_id=target_org and (public.is_org_administrator(target_org) or exists (
    select 1 from public.assignments a join public.roles role on role.id=a.role_id and role.organization_id=a.organization_id
    where a.user_id=auth.uid() and a.active and a.organization_id=target_org
      and (a.branch_id is null or a.branch_id=r.branch_id)
      and 'attendance.absences.view'=any(role.permissions)))
  order by r.updated_at desc,r.id limit 1000
$$;

revoke all on function public.my_absence_events(uuid),public.report_my_absence(uuid,text),
  public.withdraw_my_absence(uuid),public.list_reported_absences(uuid) from public,anon;
grant execute on function public.my_absence_events(uuid),public.report_my_absence(uuid,text),
  public.withdraw_my_absence(uuid),public.list_reported_absences(uuid) to authenticated;

-- Preserve the existing permission checks while allowing this new independently scoped permission.
create or replace function public.save_custom_church_role(target_org uuid, target_role uuid, role_name text, role_permissions text[])
returns uuid language plpgsql security definer set search_path = ''
as $$
declare saved_id uuid;
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only organization administrators can manage roles.'; end if;
 if role_name is null or length(trim(role_name)) not between 2 and 120 then raise exception 'Role name must be between 2 and 120 characters.'; end if;
 if lower(trim(role_name)) in ('member','visitor','branch administrator','organization administrator') then raise exception 'That name is reserved for a built-in role.'; end if;
 if role_permissions is null or array_position(role_permissions, null) is not null or exists (
   select 1 from unnest(role_permissions) p where p <> all(array[
     'members.view','members.create','members.update','members.delete',
     'visitors.view','visitors.create','visitors.update','visitors.delete',
     'attendance.view','attendance.create','attendance.absences.view'
   ]::text[])
 ) then raise exception 'One or more permissions are not supported.'; end if;
 if (role_permissions && array['members.create','members.update','members.delete']::text[] and not ('members.view'=any(role_permissions)))
   or (role_permissions && array['visitors.create','visitors.update','visitors.delete']::text[] and not ('visitors.view'=any(role_permissions)))
   or ('attendance.create'=any(role_permissions) and not ('attendance.view'=any(role_permissions))) then
   raise exception 'Select view access before granting create, edit or delete access for that area.';
 end if;
 if target_role is null then
   insert into public.roles(organization_id,name,permissions) values(target_org,trim(role_name),role_permissions) returning id into saved_id;
   insert into public.custom_church_roles(role_id,organization_id) values(saved_id,target_org);
 else
   update public.roles r set name=trim(role_name),permissions=role_permissions
   where r.id=target_role and r.organization_id=target_org
     and exists(select 1 from public.custom_church_roles c where c.role_id=r.id and c.organization_id=r.organization_id)
   returning r.id into saved_id;
   if saved_id is null then raise exception 'Custom role not found in this church.'; end if;
 end if;
 return saved_id;
end
$$;
commit;
