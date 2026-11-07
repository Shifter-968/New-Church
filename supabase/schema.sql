-- Run once in a new Supabase project's SQL editor. This does not import old data.
begin;

create extension if not exists pgcrypto;

create table public.platform_owners (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  created_at timestamptz not null default now()
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 120),
  unique (id, organization_id)
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  is_org_admin boolean not null default false,
  permissions text[] not null default '{}',
  unique (id, organization_id),
  unique (organization_id, name)
);

create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  role_id uuid not null,
  active boolean not null default true,
  foreign key (branch_id, organization_id) references public.branches(id, organization_id),
  foreign key (role_id, organization_id) references public.roles(id, organization_id)
);

create table public.members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  first_name text not null check (length(trim(first_name)) between 1 and 100),
  last_name text not null check (length(trim(last_name)) between 1 and 100),
  email text,
  phone text,
  status text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  foreign key (branch_id, organization_id) references public.branches(id, organization_id)
);

create index assignments_user_org_idx on public.assignments (user_id, organization_id) where active;
create index members_org_branch_idx on public.members (organization_id, branch_id);

create function public.is_platform_owner()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.platform_owners where user_id = auth.uid()) $$;

create function public.has_org_access(org_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_platform_owner() or exists (
    select 1 from public.assignments a
    where a.user_id = auth.uid() and a.organization_id = org_id and a.active
  )
$$;

create function public.has_member_permission(org_id uuid, member_branch_id uuid, action_name text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_platform_owner() or exists (
    select 1 from public.assignments a
    join public.roles r on r.id = a.role_id and r.organization_id = a.organization_id
    where a.user_id = auth.uid() and a.active and a.organization_id = org_id
      and (a.branch_id is null or a.branch_id = member_branch_id)
      and ((r.is_org_admin and a.branch_id is null) or ('members.' || action_name) = any(r.permissions))
  )
$$;

revoke all on function public.is_platform_owner() from public, anon;
revoke all on function public.has_org_access(uuid) from public, anon;
revoke all on function public.has_member_permission(uuid, uuid, text) from public, anon;
grant execute on function public.is_platform_owner() to authenticated;
grant execute on function public.has_org_access(uuid) to authenticated;
grant execute on function public.has_member_permission(uuid, uuid, text) to authenticated;

alter table public.platform_owners enable row level security;
alter table public.organizations enable row level security;
alter table public.branches enable row level security;
alter table public.roles enable row level security;
alter table public.assignments enable row level security;
alter table public.members enable row level security;

create policy "owners can see own owner record" on public.platform_owners for select to authenticated
  using (user_id = auth.uid());
create policy "users can see assigned organizations" on public.organizations for select to authenticated
  using (public.has_org_access(id));
create policy "owners can create organizations" on public.organizations for insert to authenticated
  with check (public.is_platform_owner());
create policy "users can see scoped branches" on public.branches for select to authenticated
  using (public.is_platform_owner() or exists (
    select 1 from public.assignments a where a.user_id = auth.uid() and a.active
      and a.organization_id = branches.organization_id and (a.branch_id is null or a.branch_id = branches.id)
  ));
create policy "users can see own assignments" on public.assignments for select to authenticated
  using (user_id = auth.uid());
create policy "users can see their roles" on public.roles for select to authenticated
  using (exists (select 1 from public.assignments a where a.user_id = auth.uid() and a.active and a.role_id = roles.id));
create policy "members view" on public.members for select to authenticated
  using (public.has_member_permission(organization_id, branch_id, 'view'));
create policy "members create" on public.members for insert to authenticated
  with check (public.has_member_permission(organization_id, branch_id, 'create'));
create policy "members update" on public.members for update to authenticated
  using (public.has_member_permission(organization_id, branch_id, 'update'))
  with check (public.has_member_permission(organization_id, branch_id, 'update'));
create policy "members delete" on public.members for delete to authenticated
  using (public.has_member_permission(organization_id, branch_id, 'delete'));

grant select on public.platform_owners, public.organizations, public.branches, public.roles, public.assignments to authenticated;
grant insert on public.organizations to authenticated;
grant select, insert, update, delete on public.members to authenticated;
commit;
