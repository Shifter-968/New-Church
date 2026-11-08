-- Apply once after 014_event_attendance.sql.
begin;

create table public.church_teams (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  kind text not null check (kind in ('ministry', 'department')),
  name text not null check (length(trim(name)) between 1 and 120),
  unique (id, organization_id),
  unique (organization_id, kind, name)
);
alter table public.members add constraint members_id_org_unique unique (id, organization_id);
alter table public.visitors add constraint visitors_id_org_unique unique (id, organization_id);
create table public.church_team_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  team_id uuid not null,
  member_id uuid,
  visitor_id uuid,
  check ((member_id is null) <> (visitor_id is null)),
  foreign key (team_id, organization_id) references public.church_teams(id, organization_id) on delete cascade,
  foreign key (member_id, organization_id) references public.members(id, organization_id) on delete cascade,
  foreign key (visitor_id, organization_id) references public.visitors(id, organization_id) on delete cascade,
  unique (team_id, member_id),
  unique (team_id, visitor_id)
);
create index church_team_members_team_idx on public.church_team_members(team_id);
alter table public.church_teams enable row level security;
alter table public.church_team_members enable row level security;
revoke all on public.church_teams, public.church_team_members from public, anon, authenticated;
grant select, insert, delete on public.church_teams, public.church_team_members to authenticated;
grant update (name) on public.church_teams to authenticated;
create policy "admin manage teams" on public.church_teams for all to authenticated
 using (public.is_org_administrator(organization_id)) with check (public.is_org_administrator(organization_id));
create policy "admin manage team members" on public.church_team_members for all to authenticated
 using (public.is_org_administrator(organization_id)) with check (public.is_org_administrator(organization_id));

alter table public.announcements add column audience_everyone boolean not null default true,
 add column audience_roles uuid[] not null default '{}', add column audience_teams uuid[] not null default '{}';
alter table public.church_events add column audience_everyone boolean not null default true,
 add column audience_roles uuid[] not null default '{}', add column audience_teams uuid[] not null default '{}';
grant update (audience_everyone, audience_roles, audience_teams) on public.announcements, public.church_events to authenticated;

create function public.validate_audience()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
 if array_position(new.audience_roles, null) is not null or array_position(new.audience_teams, null) is not null
   or cardinality(new.audience_roles) > 200 or cardinality(new.audience_teams) > 200 then
   raise exception 'Invalid audience selection.';
 end if;
 if (new.audience_everyone and (cardinality(new.audience_roles) <> 0 or cardinality(new.audience_teams) <> 0))
   or (not new.audience_everyone and cardinality(new.audience_roles) + cardinality(new.audience_teams) = 0) then
   raise exception 'Select everyone or at least one role, ministry, or department.';
 end if;
 if exists (select 1 from unnest(new.audience_roles) x(id) where not exists
   (select 1 from public.roles r where r.id=x.id and r.organization_id=new.organization_id))
   or exists (select 1 from unnest(new.audience_teams) x(id) where not exists
   (select 1 from public.church_teams t where t.id=x.id and t.organization_id=new.organization_id)) then
   raise exception 'Audience selections must belong to this church.';
 end if;
 return new;
end
$$;
revoke all on function public.validate_audience() from public, anon, authenticated;
create trigger validate_event_audience before insert or update on public.church_events for each row execute function public.validate_audience();
create trigger validate_announcement_audience before insert or update on public.announcements for each row execute function public.validate_audience();

create function public.audience_visible(target_org uuid, everyone boolean, role_ids uuid[], team_ids uuid[])
returns boolean language sql stable security definer set search_path = ''
as $$
 select public.is_org_administrator(target_org) or (
   exists (select 1 from public.assignments a where a.user_id=auth.uid() and a.active and a.organization_id=target_org)
   and (everyone or exists (select 1 from public.assignments a where a.user_id=auth.uid() and a.active
      and a.organization_id=target_org and a.role_id=any(role_ids))
    or exists (select 1 from public.church_team_members tm
      left join public.members m on m.id=tm.member_id and m.organization_id=tm.organization_id and m.status='active'
      left join public.visitors v on v.id=tm.visitor_id and v.organization_id=tm.organization_id
      where tm.organization_id=target_org and tm.team_id=any(team_ids) and (m.user_id=auth.uid() or v.user_id=auth.uid())))
 )
$$;
revoke all on function public.audience_visible(uuid, boolean, uuid[], uuid[]) from public, anon;
grant execute on function public.audience_visible(uuid, boolean, uuid[], uuid[]) to authenticated;
drop policy "assigned users read church announcements" on public.announcements;
drop policy "assigned users read church events" on public.church_events;
create policy "audience reads announcements" on public.announcements for select to authenticated
 using (public.audience_visible(organization_id, audience_everyone, audience_roles, audience_teams));
create policy "audience reads events" on public.church_events for select to authenticated
 using (public.audience_visible(organization_id, audience_everyone, audience_roles, audience_teams));

-- Roles currently have a restrictive read policy; expose only names and IDs to church admins.
create function public.audience_options(target_org uuid)
returns table (id uuid, name text, kind text)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only church administrators can manage audiences.'; end if;
 return query
 select r.id, r.name, 'role'::text from public.roles r where r.organization_id=target_org
 union all select t.id, t.name, t.kind from public.church_teams t where t.organization_id=target_org
 order by 3, 2, 1;
end
$$;
revoke all on function public.audience_options(uuid) from public, anon;
grant execute on function public.audience_options(uuid) to authenticated;

create function public.protect_audience_target()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
 if tg_table_name = 'roles' then
   if exists (select 1 from public.church_events e where old.id=any(e.audience_roles))
      or exists (select 1 from public.announcements a where old.id=any(a.audience_roles)) then
     raise exception 'This role is used by an event or announcement audience. Update those audiences first.';
   end if;
 else
   if exists (select 1 from public.church_events e where old.id=any(e.audience_teams))
      or exists (select 1 from public.announcements a where old.id=any(a.audience_teams)) then
     raise exception 'This team is used by an event or announcement audience. Update those audiences first.';
   end if;
 end if;
 return old;
end
$$;
revoke all on function public.protect_audience_target() from public, anon, authenticated;
create trigger protect_role_audience before delete on public.roles for each row execute function public.protect_audience_target();
create trigger protect_team_audience before delete on public.church_teams for each row execute function public.protect_audience_target();

create or replace function public.current_checkin_events(target_org uuid)
returns table (event_id uuid, title text, starts_at timestamptz, ends_at timestamptz, branch_name text, already_checked_in boolean)
language sql stable security definer set search_path = ''
as $$
 with person as (
  select m.id, m.branch_id, 'member'::text as kind from public.members m where m.organization_id=target_org and m.user_id=auth.uid() and m.status='active'
  union all select v.id, v.branch_id, 'visitor'::text from public.visitors v where v.organization_id=target_org and v.user_id=auth.uid()
 )
 select e.id,e.title,e.starts_at,e.ends_at,b.name,exists (select 1 from public.event_attendance a where a.event_id=e.id and
   ((p.kind='member' and a.member_id=p.id) or (p.kind='visitor' and a.visitor_id=p.id)))
 from person p join public.branches b on b.id=p.branch_id and b.organization_id=target_org
 join public.church_events e on e.organization_id=target_org
 where (select count(*) from person)=1
   and exists (select 1 from public.assignments a where a.user_id=auth.uid() and a.active and a.organization_id=target_org and (a.branch_id is null or a.branch_id=p.branch_id))
   and e.starts_at <= now() and e.ends_at >= now()
   and public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams)
 order by e.starts_at,e.id limit 100
$$;

alter function public.self_check_in(uuid, double precision, double precision) rename to self_check_in_unfiltered;
revoke all on function public.self_check_in_unfiltered(uuid, double precision, double precision) from public, anon, authenticated;
create function public.self_check_in(target_event uuid, device_latitude double precision, device_longitude double precision)
returns void language plpgsql security definer set search_path = ''
as $$
begin
 if not exists (select 1 from public.church_events e where e.id=target_event and
   public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams)) then
   raise exception 'This event is not available to your account.';
 end if;
 perform public.self_check_in_unfiltered(target_event,device_latitude,device_longitude);
end
$$;
alter function public.admin_check_in(uuid, text, uuid) rename to admin_check_in_unfiltered;
revoke all on function public.admin_check_in_unfiltered(uuid, text, uuid) from public, anon, authenticated;
create function public.admin_check_in(target_event uuid, person_kind text, person_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
 if not exists (select 1 from public.church_events e where e.id=target_event and
   public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams)) then
   raise exception 'This event is not available to your account.';
 end if;
 perform public.admin_check_in_unfiltered(target_event,person_kind,person_id);
end
$$;
alter function public.list_event_attendance(uuid, uuid) rename to list_event_attendance_unfiltered;
revoke all on function public.list_event_attendance_unfiltered(uuid, uuid) from public, anon, authenticated;
create function public.list_event_attendance(target_org uuid, target_event uuid)
returns table (id uuid, person_kind text, first_name text, last_name text, branch_id uuid, checked_in_at timestamptz, method text)
language sql stable security definer set search_path = ''
as $$
 select a.* from public.list_event_attendance_unfiltered(target_org,target_event) a
 where exists (select 1 from public.church_events e where e.id=target_event and e.organization_id=target_org
   and public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams))
$$;
revoke all on function public.self_check_in(uuid,double precision,double precision), public.admin_check_in(uuid,text,uuid), public.list_event_attendance(uuid,uuid) from public, anon;
grant execute on function public.self_check_in(uuid,double precision,double precision), public.admin_check_in(uuid,text,uuid), public.list_event_attendance(uuid,uuid) to authenticated;
commit;
