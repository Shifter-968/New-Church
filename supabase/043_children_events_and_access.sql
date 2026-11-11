-- Apply once after 042_attendance_window_and_member_phone_match.sql.
begin;

create or replace function public.has_children_permission(org_id uuid, target_branch uuid, action_name text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.has_member_permission(org_id, target_branch, action_name)
    or public.is_platform_owner()
    or exists (
      select 1 from public.assignments a
      join public.roles r on r.id = a.role_id and r.organization_id = a.organization_id
      where a.user_id = auth.uid() and a.active and a.organization_id = org_id
        and (a.branch_id is null or a.branch_id = target_branch)
        and ((r.is_org_admin and a.branch_id is null) or ('children.' || action_name) = any(r.permissions))
    )
$$;
revoke all on function public.has_children_permission(uuid, uuid, text) from public, anon;
grant execute on function public.has_children_permission(uuid, uuid, text) to authenticated;

create or replace function public.enforce_single_active_assignment()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.active then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text || ':active-assignment', 0));
    if exists (
      select 1 from public.assignments a
      where a.user_id = new.user_id and a.active
        and a.organization_id <> new.organization_id and a.id is distinct from new.id
    ) then
      raise exception 'This account already has an active church assignment. Use a different email for another church.';
    end if;
  end if;
  return new;
end
$$;

drop policy "children view" on public.church_children;
drop policy "children create" on public.church_children;
drop policy "children update" on public.church_children;
drop policy "children delete" on public.church_children;
create policy "children view" on public.church_children for select to authenticated
  using (public.has_children_permission(organization_id, branch_id, 'view'));
create policy "children create" on public.church_children for insert to authenticated
  with check (public.has_children_permission(organization_id, branch_id, 'create'));
create policy "children update" on public.church_children for update to authenticated
  using (public.has_children_permission(organization_id, branch_id, 'update'))
  with check (public.has_children_permission(organization_id, branch_id, 'update'));
create policy "children delete" on public.church_children for delete to authenticated
  using (public.has_children_permission(organization_id, branch_id, 'delete'));

create table public.church_children_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  branch_id uuid not null,
  title text not null check (length(trim(title)) between 1 and 200),
  description text not null default '' check (length(description) <= 5000),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  foreign key (branch_id, organization_id) references public.branches(id, organization_id),
  unique (id, organization_id, branch_id)
);

create table public.church_children_event_attendance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  branch_id uuid not null,
  event_id uuid not null,
  child_id uuid not null,
  checked_in_at timestamptz not null default now(),
  checked_in_by uuid not null default auth.uid() references auth.users(id),
  foreign key (event_id, organization_id, branch_id)
    references public.church_children_events(id, organization_id, branch_id) on delete restrict,
  foreign key (child_id, organization_id, branch_id)
    references public.church_children(id, organization_id, branch_id) on delete restrict,
  unique (event_id, child_id)
);

create index church_children_events_branch_start_idx
  on public.church_children_events(organization_id, branch_id, starts_at desc);
create index church_children_event_attendance_event_idx
  on public.church_children_event_attendance(event_id, checked_in_at desc);

alter table public.church_children_events enable row level security;
alter table public.church_children_event_attendance enable row level security;
revoke all on public.church_children_events, public.church_children_event_attendance from public, anon, authenticated;
grant select, delete on public.church_children_events to authenticated;
grant insert (organization_id, branch_id, title, description, starts_at, ends_at) on public.church_children_events to authenticated;
grant update (title, description, starts_at, ends_at) on public.church_children_events to authenticated;
grant select on public.church_children_event_attendance to authenticated;

create policy "children events view" on public.church_children_events for select to authenticated
  using (public.has_children_permission(organization_id, branch_id, 'view'));
create policy "children events create" on public.church_children_events for insert to authenticated
  with check (public.has_children_permission(organization_id, branch_id, 'create'));
create policy "children events update" on public.church_children_events for update to authenticated
  using (public.has_children_permission(organization_id, branch_id, 'update'))
  with check (public.has_children_permission(organization_id, branch_id, 'update'));
create policy "children events delete" on public.church_children_events for delete to authenticated
  using (public.has_children_permission(organization_id, branch_id, 'delete'));
create policy "children event attendance view" on public.church_children_event_attendance for select to authenticated
  using (public.has_children_permission(organization_id, branch_id, 'view'));

create function public.mark_child_event_attendance(target_event uuid, target_child uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare ev public.church_children_events%rowtype; child_branch uuid; attendance_id uuid;
begin
  select * into ev from public.church_children_events where id = target_event;
  if not found then raise exception 'Children event not found.'; end if;
  select c.branch_id into child_branch from public.church_children c
    where c.id = target_child and c.organization_id = ev.organization_id;
  if child_branch is null or child_branch <> ev.branch_id then
    raise exception 'Child and event must belong to the same branch.';
  end if;
  if not public.has_children_permission(ev.organization_id, ev.branch_id, 'create') then
    raise exception 'You do not have permission to record children attendance.';
  end if;
  if now() < ev.starts_at or now() > ev.ends_at then
    raise exception 'Children attendance can only be recorded while the event is ongoing.';
  end if;
  insert into public.church_children_event_attendance
    (organization_id, branch_id, event_id, child_id, checked_in_by)
  values (ev.organization_id, ev.branch_id, ev.id, target_child, auth.uid())
  on conflict (event_id, child_id) do nothing
  returning id into attendance_id;
  if attendance_id is null then raise exception 'This child is already marked present for this event.'; end if;
  return attendance_id;
end
$$;

create function public.remove_child_event_attendance(target_attendance uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.church_children_event_attendance a
    where a.id = target_attendance
      and public.has_children_permission(a.organization_id, a.branch_id, 'update');
  if not found then raise exception 'Attendance record not found or you do not have permission to remove it.'; end if;
end
$$;

revoke all on function public.mark_child_event_attendance(uuid, uuid),
  public.remove_child_event_attendance(uuid) from public, anon;
grant execute on function public.mark_child_event_attendance(uuid, uuid),
  public.remove_child_event_attendance(uuid) to authenticated;

create trigger children_event_activity after insert or update or delete
  on public.church_children_events for each row execute function public.record_support_activity();
create trigger children_event_attendance_activity after insert or delete
  on public.church_children_event_attendance for each row execute function public.record_support_activity();

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
     'children.view','children.create','children.update','children.delete',
     'attendance.view','attendance.create'
   ]::text[])
 ) then raise exception 'One or more permissions are not supported.'; end if;
 if (role_permissions && array['members.create','members.update','members.delete']::text[] and not ('members.view'=any(role_permissions)))
   or (role_permissions && array['visitors.create','visitors.update','visitors.delete']::text[] and not ('visitors.view'=any(role_permissions)))
   or (role_permissions && array['children.create','children.update','children.delete']::text[] and not ('children.view'=any(role_permissions)))
   or ('attendance.create'=any(role_permissions) and not ('attendance.view'=any(role_permissions))) then
   raise exception 'Select view access before granting create, edit or delete access for that area.';
 end if;
 if target_role is null then
   insert into public.roles(organization_id,name,permissions) values(target_org,trim(role_name),role_permissions) returning id into saved_id;
   insert into public.custom_church_roles(role_id,organization_id) values(saved_id,target_org);
 else
   update public.roles r set name=trim(role_name),permissions=role_permissions
   where r.id=target_role and r.organization_id=target_org
     and exists(select 1 from public.custom_church_roles c where c.role_id=r.id and c.organization_id=target_org)
   returning r.id into saved_id;
   if saved_id is null then raise exception 'Custom role not found in this church.'; end if;
 end if;
 return saved_id;
end
$$;

commit;
