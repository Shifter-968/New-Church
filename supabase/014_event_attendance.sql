-- Apply once after 013_branch_location.sql.
begin;

update public.roles set permissions = array['members.view','members.create','members.update','members.delete',
 'visitors.view','visitors.create','visitors.update','visitors.delete','attendance.view','attendance.create']
where name = 'Branch Administrator' and not is_org_admin
 and permissions = array['members.view','members.create','members.update','members.delete','visitors.view','visitors.create','visitors.update','visitors.delete'];

create or replace function public.assign_branch_administrator(org_id uuid, target_branch_id uuid, target_user_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare admin_role_id uuid;
begin
 if not public.is_org_administrator(org_id) then raise exception 'Only an organization administrator or platform owner can assign branch administrators'; end if;
 if not exists (select 1 from public.branches where id = target_branch_id and organization_id = org_id) then raise exception 'Branch does not belong to this organization'; end if;
 if not exists (select 1 from auth.users where id = target_user_id) then raise exception 'The user account does not exist'; end if;
 insert into public.roles (organization_id, name, permissions) values (org_id, 'Branch Administrator',
   array['members.view','members.create','members.update','members.delete','visitors.view','visitors.create','visitors.update','visitors.delete','attendance.view','attendance.create'])
 on conflict (organization_id, name) do nothing;
 select id into admin_role_id from public.roles where organization_id = org_id and name = 'Branch Administrator' and not is_org_admin
   and permissions = array['members.view','members.create','members.update','members.delete','visitors.view','visitors.create','visitors.update','visitors.delete','attendance.view','attendance.create'];
 if admin_role_id is null then raise exception 'The Branch Administrator role conflicts with the expected permissions'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(org_id::text || target_branch_id::text || target_user_id::text, 0));
 if exists (select 1 from public.assignments where user_id = target_user_id and organization_id = org_id and branch_id = target_branch_id and role_id = admin_role_id and active) then
   raise exception 'This user is already a branch administrator for this branch';
 end if;
 insert into public.assignments (user_id, organization_id, branch_id, role_id) values (target_user_id, org_id, target_branch_id, admin_role_id);
end
$$;

create function public.has_attendance_permission(org_id uuid, target_branch uuid, action_name text)
returns boolean language sql stable security definer set search_path = ''
as $$
 select public.is_platform_owner() or exists (
   select 1 from public.assignments a join public.roles r on r.id = a.role_id and r.organization_id = a.organization_id
   where a.user_id = auth.uid() and a.active and a.organization_id = org_id
     and (a.branch_id is null or a.branch_id = target_branch)
     and ((a.branch_id is null and r.is_org_admin) or ('attendance.' || action_name) = any(r.permissions))
 )
$$;
revoke all on function public.has_attendance_permission(uuid, uuid, text) from public, anon;
grant execute on function public.has_attendance_permission(uuid, uuid, text) to authenticated;

create table public.event_attendance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  event_id uuid not null references public.church_events(id) on delete restrict,
  branch_id uuid not null,
  member_id uuid references public.members(id) on delete restrict,
  visitor_id uuid references public.visitors(id) on delete restrict,
  checked_in_at timestamptz not null default now(),
  checked_in_by uuid not null references auth.users(id),
  method text not null check (method in ('self', 'admin')),
  check ((member_id is null) <> (visitor_id is null)),
  foreign key (branch_id, organization_id) references public.branches(id, organization_id),
  unique (event_id, member_id),
  unique (event_id, visitor_id)
);
create index event_attendance_org_branch_idx on public.event_attendance (organization_id, branch_id, checked_in_at desc);
alter table public.event_attendance enable row level security;
revoke all on public.event_attendance from public, anon, authenticated;

create function public.current_checkin_events(target_org uuid)
returns table (event_id uuid, title text, starts_at timestamptz, ends_at timestamptz, branch_name text, already_checked_in boolean)
language sql stable security definer set search_path = ''
as $$
  with person as (
    select m.id, m.branch_id, 'member'::text as kind from public.members m
      where m.organization_id = target_org and m.user_id = auth.uid() and m.status = 'active'
    union all
    select v.id, v.branch_id, 'visitor'::text from public.visitors v
      where v.organization_id = target_org and v.user_id = auth.uid()
  )
  select e.id, e.title, e.starts_at, e.ends_at, b.name,
    exists (select 1 from public.event_attendance a where a.event_id = e.id and
      ((p.kind = 'member' and a.member_id = p.id) or (p.kind = 'visitor' and a.visitor_id = p.id)))
  from person p join public.branches b on b.id = p.branch_id and b.organization_id = target_org
  join public.church_events e on e.organization_id = target_org
  where (select count(*) from person) = 1
    and exists (select 1 from public.assignments a where a.user_id = auth.uid() and a.active and a.organization_id = target_org and (a.branch_id is null or a.branch_id = p.branch_id))
    and e.starts_at <= now() and e.ends_at >= now()
  order by e.starts_at, e.id limit 100
$$;

create function public.self_check_in(target_event uuid, device_latitude double precision, device_longitude double precision)
returns void language plpgsql security definer set search_path = ''
as $$
declare ev public.church_events%rowtype; person record; person_count integer; loc public.branches%rowtype; h double precision; distance double precision;
begin
 if auth.uid() is null then raise exception 'Sign in to check in.'; end if;
 select * into ev from public.church_events where id = target_event;
 if not found then raise exception 'Event not found.'; end if;
 if now() < ev.starts_at or now() > ev.ends_at then raise exception 'Check-in is only available while the event is ongoing.'; end if;
 if device_latitude is null or device_longitude is null or device_latitude not between -90 and 90 or device_longitude not between -180 and 180 then
   raise exception 'A valid device location is required.';
 end if;
 select count(*) into person_count from (
   select id from public.members where organization_id = ev.organization_id and user_id = auth.uid() and status = 'active'
   union all select id from public.visitors where organization_id = ev.organization_id and user_id = auth.uid()
 ) p;
 if person_count <> 1 then raise exception 'An unambiguous linked member or visitor record is required. Contact your church administrator.'; end if;
 select * into person from (
   select id, branch_id, 'member'::text as kind from public.members where organization_id = ev.organization_id and user_id = auth.uid() and status = 'active'
   union all select id, branch_id, 'visitor'::text from public.visitors where organization_id = ev.organization_id and user_id = auth.uid()
 ) p;
 if person.branch_id is null or not exists (select 1 from public.assignments a where a.user_id = auth.uid() and a.active and a.organization_id = ev.organization_id and (a.branch_id is null or a.branch_id = person.branch_id)) then
   raise exception 'A valid branch assignment is required for check-in.';
 end if;
 select * into loc from public.branches where id = person.branch_id and organization_id = ev.organization_id;
 if loc.latitude is null or loc.longitude is null then raise exception 'Your branch location has not been configured. Contact your church administrator.'; end if;
 h := power(sin(radians(device_latitude - loc.latitude::double precision) / 2), 2)
    + cos(radians(loc.latitude::double precision)) * cos(radians(device_latitude)) * power(sin(radians(device_longitude - loc.longitude::double precision) / 2), 2);
 distance := 12742000 * asin(sqrt(least(1.0, greatest(0.0, h))));
 if distance > loc.radius_meters then raise exception 'You are outside your branch check-in radius.'; end if;
 insert into public.event_attendance (organization_id, event_id, branch_id, member_id, visitor_id, checked_in_by, method)
 values (ev.organization_id, ev.id, person.branch_id, case when person.kind = 'member' then person.id end, case when person.kind = 'visitor' then person.id end, auth.uid(), 'self')
 on conflict do nothing;
 if not found then raise exception 'You are already checked in for this event.'; end if;
end
$$;

create function public.admin_check_in(target_event uuid, person_kind text, person_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare ev public.church_events%rowtype; branch uuid;
begin
 select * into ev from public.church_events where id = target_event;
 if not found then raise exception 'Event not found.'; end if;
 if person_kind = 'member' then
   select branch_id into branch from public.members where id = person_id and organization_id = ev.organization_id and status = 'active';
 elsif person_kind = 'visitor' then
   select branch_id into branch from public.visitors where id = person_id and organization_id = ev.organization_id;
 else raise exception 'Invalid person type.'; end if;
 if branch is null then raise exception 'Person not found or has no branch.'; end if;
 if not public.has_attendance_permission(ev.organization_id, branch, 'create')
   or (person_kind = 'member' and not public.has_member_permission(ev.organization_id, branch, 'view'))
   or (person_kind = 'visitor' and not public.has_visitor_permission(ev.organization_id, branch, 'view')) then
   raise exception 'You do not have permission to check in this person.';
 end if;
 insert into public.event_attendance (organization_id, event_id, branch_id, member_id, visitor_id, checked_in_by, method)
 values (ev.organization_id, ev.id, branch, case when person_kind = 'member' then person_id end, case when person_kind = 'visitor' then person_id end, auth.uid(), 'admin')
 on conflict do nothing;
 if not found then raise exception 'This person is already checked in for this event.'; end if;
end
$$;

create function public.list_event_attendance(target_org uuid, target_event uuid)
returns table (id uuid, person_kind text, first_name text, last_name text, branch_id uuid, checked_in_at timestamptz, method text)
language sql stable security definer set search_path = ''
as $$
 select a.id, case when a.member_id is not null then 'member' else 'visitor' end,
   coalesce(m.first_name, v.first_name), coalesce(m.last_name, v.last_name),
   a.branch_id, a.checked_in_at, a.method
 from public.event_attendance a
 left join public.members m on m.id = a.member_id
 left join public.visitors v on v.id = a.visitor_id
 where a.organization_id = target_org and a.event_id = target_event
   and public.has_attendance_permission(a.organization_id, a.branch_id, 'view')
   and ((a.member_id is not null and public.has_member_permission(a.organization_id, a.branch_id, 'view'))
     or (a.visitor_id is not null and public.has_visitor_permission(a.organization_id, a.branch_id, 'view')))
 order by a.checked_in_at desc, a.id limit 1000
$$;
revoke all on function public.current_checkin_events(uuid), public.self_check_in(uuid, double precision, double precision),
 public.admin_check_in(uuid, text, uuid), public.list_event_attendance(uuid, uuid) from public, anon;
grant execute on function public.current_checkin_events(uuid), public.self_check_in(uuid, double precision, double precision),
 public.admin_check_in(uuid, text, uuid), public.list_event_attendance(uuid, uuid) to authenticated;
commit;
