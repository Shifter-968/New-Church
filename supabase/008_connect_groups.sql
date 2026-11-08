-- Apply once after 007_support_management.sql.
begin;

create table public.connect_groups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  name text not null check (length(trim(name)) between 1 and 255),
  description text not null default '' check (length(description) <= 10000),
  owner_id uuid not null references auth.users(id),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'ARCHIVED', 'SUSPENDED')),
  join_code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
  created_at timestamptz not null default now(),
  foreign key (branch_id, organization_id) references public.branches(id, organization_id)
);

create table public.connect_members (
  connect_id uuid not null references public.connect_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('CREATOR', 'MEMBER')),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE', 'BANNED')),
  joined_at timestamptz not null default now(),
  primary key (connect_id, user_id)
);
create index connect_groups_org_idx on public.connect_groups (organization_id, created_at desc);
create index connect_members_user_idx on public.connect_members (user_id, status);
alter table public.connect_groups enable row level security;
alter table public.connect_members enable row level security;
revoke all on public.connect_groups, public.connect_members from public, anon, authenticated;

create function public.connect_has_assignment(target_user uuid, target_org uuid, target_branch uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.assignments a where a.user_id = target_user
    and a.organization_id = target_org and a.active
    and (target_branch is null or a.branch_id is null or a.branch_id = target_branch))
$$;
revoke all on function public.connect_has_assignment(uuid, uuid, uuid) from public, anon, authenticated;

create function public.list_connect_groups(target_org uuid default null)
returns table (id uuid, organization_id uuid, branch_id uuid, branch_name text, name text, description text,
  owner_id uuid, owner_email text, status text, join_code text, member_count bigint, my_role text, created_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select c.id, c.organization_id, c.branch_id, b.name, c.name, c.description, c.owner_id,
    case when public.is_org_administrator(c.organization_id) or c.owner_id = auth.uid() then u.email::text else null end,
    c.status, case when m.status = 'ACTIVE' then c.join_code else null end,
    (select count(*) from public.connect_members cm where cm.connect_id = c.id and cm.status = 'ACTIVE'),
    case when m.status = 'ACTIVE' then m.role else null end, c.created_at
  from public.connect_groups c
  join auth.users u on u.id = c.owner_id
  left join public.branches b on b.id = c.branch_id and b.organization_id = c.organization_id
  left join public.connect_members m on m.connect_id = c.id and m.user_id = auth.uid()
  where (target_org is null or c.organization_id = target_org)
    and (public.is_org_administrator(c.organization_id)
      or (m.status = 'ACTIVE' and public.connect_has_assignment(auth.uid(), c.organization_id, c.branch_id)))
  order by c.created_at desc, c.id desc limit 100
$$;

create function public.save_connect_group(target_id uuid, target_org uuid, target_branch uuid,
  group_name text, group_description text, group_status text, owner_email text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare existing public.connect_groups%rowtype; chosen_owner uuid; group_id uuid; admin boolean;
begin
  if auth.uid() is null or target_org is null then raise exception 'Choose a church and sign in.'; end if;
  admin := public.is_org_administrator(target_org);
  if target_branch is not null and not exists
    (select 1 from public.branches b where b.id = target_branch and b.organization_id = target_org) then
    raise exception 'The branch does not belong to this church.';
  end if;
  if target_id is not null then
    select * into existing from public.connect_groups c where c.id = target_id for update;
    if not found or existing.organization_id <> target_org then raise exception 'Connect not found.'; end if;
    if not admin and not (existing.owner_id = auth.uid()
      and public.connect_has_assignment(auth.uid(), target_org, existing.branch_id)) then
      raise exception 'You cannot edit this Connect.';
    end if;
  elsif not admin and not public.connect_has_assignment(auth.uid(), target_org, target_branch) then
    raise exception 'An active church assignment is required to create a Connect.';
  end if;
  if not admin then
    if target_id is not null and (target_branch is distinct from existing.branch_id or group_status <> existing.status) then
      raise exception 'Only an administrator can change the branch or status.';
    end if;
    chosen_owner := auth.uid();
  else
    select u.id into chosen_owner from auth.users u where lower(u.email) = lower(trim(owner_email))
      and u.email_confirmed_at is not null;
  end if;
  if not admin and target_id is null and group_status <> 'ACTIVE' then
    raise exception 'New Connects must be active.';
  end if;
  if chosen_owner is null or not public.connect_has_assignment(chosen_owner, target_org, target_branch) then
    raise exception 'The Connect owner must be a confirmed account with an active assignment in this church and branch.';
  end if;
  if target_id is not null and target_branch is distinct from existing.branch_id and exists (
    select 1 from public.connect_members m where m.connect_id = target_id and m.status = 'ACTIVE'
      and m.user_id <> chosen_owner and not public.connect_has_assignment(m.user_id, target_org, target_branch)
  ) then raise exception 'The branch cannot be changed while active members lack access to the new branch.'; end if;
  if target_id is null then
    insert into public.connect_groups (organization_id, branch_id, name, description, owner_id, status)
      values (target_org, target_branch, trim(group_name), coalesce(trim(group_description), ''), chosen_owner, group_status)
      returning id into group_id;
  else
    group_id := target_id;
    update public.connect_groups set branch_id = target_branch, name = trim(group_name),
      description = coalesce(trim(group_description), ''), owner_id = chosen_owner, status = group_status
      where id = target_id;
    if existing.owner_id <> chosen_owner then
      update public.connect_members set role = 'MEMBER' where connect_id = target_id and user_id = existing.owner_id;
    end if;
  end if;
  insert into public.connect_members (connect_id, user_id, role, status)
    values (group_id, chosen_owner, 'CREATOR', 'ACTIVE')
    on conflict (connect_id, user_id) do update set role = 'CREATOR', status = 'ACTIVE';
  return group_id;
end
$$;

create function public.join_connect_group(target_org uuid, code text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare group_row public.connect_groups%rowtype; membership public.connect_members%rowtype;
begin
  select * into group_row from public.connect_groups c
    where c.organization_id = target_org and c.join_code = upper(trim(code)) and c.status = 'ACTIVE' for update;
  if not found or not public.connect_has_assignment(auth.uid(), group_row.organization_id, group_row.branch_id) then
    raise exception 'Invalid code or you do not have an active assignment for this Connect.';
  end if;
  select * into membership from public.connect_members m where m.connect_id = group_row.id and m.user_id = auth.uid();
  if found and membership.status = 'BANNED' then raise exception 'You cannot join this Connect.'; end if;
  if found and membership.status = 'ACTIVE' then raise exception 'You already belong to this Connect.'; end if;
  insert into public.connect_members (connect_id, user_id, role, status)
    values (group_row.id, auth.uid(), 'MEMBER', 'ACTIVE')
    on conflict (connect_id, user_id) do update set status = 'ACTIVE', role = 'MEMBER', joined_at = now();
  return group_row.id;
end
$$;

create function public.delete_connect_group(target_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare group_row public.connect_groups%rowtype;
begin
  select * into group_row from public.connect_groups c where c.id = target_id for update;
  if not found then raise exception 'Connect not found.'; end if;
  if not public.is_org_administrator(group_row.organization_id) and not
    (group_row.owner_id = auth.uid() and public.connect_has_assignment(auth.uid(), group_row.organization_id, group_row.branch_id)) then
    raise exception 'You cannot delete this Connect.';
  end if;
  delete from public.connect_groups where id = target_id;
end
$$;

revoke all on function public.list_connect_groups(uuid), public.save_connect_group(uuid, uuid, uuid, text, text, text, text),
  public.join_connect_group(uuid, text), public.delete_connect_group(uuid) from public, anon;
grant execute on function public.list_connect_groups(uuid), public.save_connect_group(uuid, uuid, uuid, text, text, text, text),
  public.join_connect_group(uuid, text), public.delete_connect_group(uuid) to authenticated;
create trigger connect_group_activity after insert or update or delete on public.connect_groups
  for each row execute function public.record_support_activity();
commit;
