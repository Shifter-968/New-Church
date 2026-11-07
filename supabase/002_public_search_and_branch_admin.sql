-- Apply after schema.sql. Public discovery exposes church and branch names only.
begin;

alter table public.organizations add column if not exists is_discoverable boolean not null default true;

create function public.search_public_churches(search_term text)
returns table (id uuid, name text)
language sql stable security definer set search_path = ''
as $$
  select o.id, o.name from public.organizations o
  where o.is_discoverable and length(trim(search_term)) >= 2
    and strpos(lower(o.name), lower(trim(search_term))) > 0
  order by o.name, o.id limit 25
$$;

create function public.public_church_branches(church_id uuid)
returns table (id uuid, name text)
language sql stable security definer set search_path = ''
as $$
  select b.id, b.name from public.branches b
  join public.organizations o on o.id = b.organization_id
  where o.id = church_id and o.is_discoverable
  order by b.name, b.id
$$;

create function public.is_org_administrator(org_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_platform_owner() or exists (
    select 1 from public.assignments a
    join public.roles r on r.id = a.role_id and r.organization_id = a.organization_id
    where a.user_id = auth.uid() and a.active and a.organization_id = org_id
      and a.branch_id is null and r.is_org_admin
  )
$$;

create function public.assign_branch_administrator(org_id uuid, target_branch_id uuid, target_user_id uuid)
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
    values (org_id, 'Branch Administrator', array['members.view','members.create','members.update','members.delete'])
    on conflict (organization_id, name) do nothing;
  select id into admin_role_id from public.roles
    where organization_id = org_id and name = 'Branch Administrator'
      and not is_org_admin
      and permissions = array['members.view','members.create','members.update','members.delete'];
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

revoke all on function public.search_public_churches(text) from public;
revoke all on function public.public_church_branches(uuid) from public;
revoke all on function public.is_org_administrator(uuid) from public, anon;
revoke all on function public.assign_branch_administrator(uuid, uuid, uuid) from public, anon;
grant execute on function public.search_public_churches(text), public.public_church_branches(uuid) to anon, authenticated;
grant execute on function public.is_org_administrator(uuid), public.assign_branch_administrator(uuid, uuid, uuid) to authenticated;

create policy "organization administrators can create branches" on public.branches for insert to authenticated
  with check (public.is_org_administrator(organization_id));
grant insert on public.branches to authenticated;
commit;
