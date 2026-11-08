-- Apply once after 010_individual_registration.sql.
begin;

-- Only upgrade the exact built-in role; custom or conflicting roles are left untouched.
update public.roles
set permissions = array['members.view','members.create','members.update','members.delete',
                        'visitors.view','visitors.create','visitors.update','visitors.delete']
where name = 'Branch Administrator' and not is_org_admin
  and permissions = array['members.view','members.create','members.update','members.delete'];

create or replace function public.assign_branch_administrator(org_id uuid, target_branch_id uuid, target_user_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare admin_role_id uuid;
begin
  if not public.is_org_administrator(org_id) then
    raise exception 'Only an organization administrator or platform owner can assign branch administrators';
  end if;
  if not exists (select 1 from public.branches where id = target_branch_id and organization_id = org_id) then
    raise exception 'Branch does not belong to this organization';
  end if;
  if not exists (select 1 from auth.users where id = target_user_id) then
    raise exception 'The user account does not exist';
  end if;
  insert into public.roles (organization_id, name, permissions)
    values (org_id, 'Branch Administrator', array['members.view','members.create','members.update','members.delete',
                                                'visitors.view','visitors.create','visitors.update','visitors.delete'])
    on conflict (organization_id, name) do nothing;
  select id into admin_role_id from public.roles
    where organization_id = org_id and name = 'Branch Administrator' and not is_org_admin
      and permissions = array['members.view','members.create','members.update','members.delete',
                              'visitors.view','visitors.create','visitors.update','visitors.delete'];
  if admin_role_id is null then
    raise exception 'The Branch Administrator role conflicts with the expected permissions';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(org_id::text || target_branch_id::text || target_user_id::text, 0));
  if exists (select 1 from public.assignments where user_id = target_user_id and organization_id = org_id
      and branch_id = target_branch_id and role_id = admin_role_id and active) then
    raise exception 'This user is already a branch administrator for this branch';
  end if;
  insert into public.assignments (user_id, organization_id, branch_id, role_id)
    values (target_user_id, org_id, target_branch_id, admin_role_id);
end
$$;

alter table public.visitors alter column email drop not null;
alter table public.visitors alter column phone drop not null;

create function public.has_visitor_permission(org_id uuid, visitor_branch_id uuid, action_name text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_platform_owner() or exists (
    select 1 from public.assignments a
    join public.roles r on r.id = a.role_id and r.organization_id = a.organization_id
    where a.user_id = auth.uid() and a.active and a.organization_id = org_id
      and (a.branch_id is null or a.branch_id = visitor_branch_id)
      and ((r.is_org_admin and a.branch_id is null) or ('visitors.' || action_name) = any(r.permissions))
  )
$$;
revoke all on function public.has_visitor_permission(uuid, uuid, text) from public, anon;
grant execute on function public.has_visitor_permission(uuid, uuid, text) to authenticated;

create policy "visitors view" on public.visitors for select to authenticated
  using (public.has_visitor_permission(organization_id, branch_id, 'view'));
create policy "visitors create" on public.visitors for insert to authenticated
  with check (public.has_visitor_permission(organization_id, branch_id, 'create'));
create policy "visitors update" on public.visitors for update to authenticated
  using (public.has_visitor_permission(organization_id, branch_id, 'update'))
  with check (public.has_visitor_permission(organization_id, branch_id, 'update'));
create policy "visitors delete" on public.visitors for delete to authenticated
  using (public.has_visitor_permission(organization_id, branch_id, 'delete'));

grant select, delete on public.visitors to authenticated;
grant insert (organization_id, branch_id, first_name, last_name, email, phone) on public.visitors to authenticated;
grant update (branch_id, first_name, last_name, email, phone) on public.visitors to authenticated;

create function public.protect_linked_visitor_assignment()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.user_id is not null then
      raise exception 'Linked visitors cannot be deleted until account access management is available.';
    end if;
    return old;
  end if;
  if old.user_id is not null and new.branch_id is distinct from old.branch_id then
    raise exception 'A linked visitor branch cannot be changed until account access management is available.';
  end if;
  return new;
end
$$;
revoke all on function public.protect_linked_visitor_assignment() from public, anon, authenticated;
create trigger protect_linked_visitor_assignment before update or delete on public.visitors
  for each row execute function public.protect_linked_visitor_assignment();
commit;
